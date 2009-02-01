#--
# Copyright (C) 2008 Dimitrij Denissenko
# Please read LICENSE document for more information.
#++
class Repository::Git < Repository::Abstract

  class << self
    
    def truncate_revision(revision)
      super.first(6)
    end
    
  end

  def active?
    SCM_GIT_ENABLED and super
  end

  def latest_revision
    'HEAD'
  end

  def unified_diff(path, revision_a, revision_b)
    return '' unless active?

    text = repo.git.run '', 'diff', '', {}, [revision_a, revision_b, '--', path]
    list = Grit::Diff.list_from_string(repo, text).first
    return '' unless list.present? and list.diff.to_s.starts_with?('--- ')
    
    "--- Revision #{revision_a}\n+++ Revision #{revision_b}\n" + list.diff.
      gsub(/\A\-{3} .+?\n/, '').
      gsub(/\A\+{3} .+?\n/, '')    
  end

  # Returns the revision history for a path starting with a given revision
  def history(path, revision = nil, limit = 100)
    return [] unless active? 
    
    repo.log(revision || latest_revision, path, :n => limit).map(&:id)
  end

  def sync_changesets
    return unless active?

    last_changeset = changesets.find :first, :select => 'revision', :order => 'created_at DESC'
    revisions = if last_changeset and last_commit = repo.commit(last_changeset.revision) and head = repo.commits('master', 1).first      
      repo.commits_between(last_commit, head)
    else
      repo.commits('HEAD', nil).reverse
    end.map(&:id)

    log :debug, 'SYNC', "Revisions: #{revisions.first} - #{revisions.last}"    
    revisions.each do |revision|
      create_changeset!(revision)
    end

    Changeset.update_project_associations!
  end

  def repo
    @repo ||= Grit::Repo.new(path.chomp('/'))
  end

  protected 

    def new_changeset(revision)
      commit = repo.commit(revision)
            
      node_data = { :added => [], :copied => [], :updated => [], :deleted => [], :moved => [] }

      commit.file_changes.each do |change|
        case change.type
        when 'A'
          node_data[:added] << change.a_path          
        when 'D'
          node_data[:deleted] << change.a_path
        when 'M'
          node_data[:updated] << change.a_path
        when 'C'          
          node_data[:copied] << [change.b_path, change.a_path, commit.parents.first.id]
        when 'R'
          node_data[:moved] << [change.b_path, change.a_path, commit.parents.first.id]
        end
      end
      
      changeset = changesets.build :revision => revision.to_s, 
        :author => commit.committer.name, 
        :log => commit.message, 
        :created_at => commit.committed_date      
      changeset.skip_project_synchronization = true
      [changeset, node_data]
    end

end
