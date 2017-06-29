# You can define any Rake tasks to support your application here (or in any file
# ending in .rake in this directory).
#
# Rake (Ruby Make) is very useful for creating build scripts, see this short video
# for a quick introduction:
# http://railscasts.com/episodes/66-custom-rake-tasks

namespace :isc do
  desc 'Remove back-up files recursively from the project'
  task :clean do
    backup_files = Dir.glob("#{Origen.root}/**/*~")
    unless backup_files.empty?
      puts 'Backup files removed:'
      puts backup_files.join("\n")
      File.delete(*backup_files)
    end
  end

  desc 'Find unmanaged files'
  task :find_unman do
    root_path = Origen.root.to_s.split('/').drop(1)
    Origen.app.rc.unmanaged.each do |f|
      next if f =~ /\~/
      path = f.split('/').drop(1)
      proj_sub_dir = (path - root_path).first
      next if proj_sub_dir =~ /^\.|^web$|^lbin$|^log$/
      puts f
    end
  end

  desc 'Find unmanaged files and commit to revision control'
  task :commit_unman do
    root_path = Origen.root.to_s.split('/').drop(1)
    files = []
    Origen.app.rc.unmanaged.each do |f|
      next if f =~ /\~/
      path = f.split('/').drop(1)
      proj_sub_dir = (path - root_path).first
      next if proj_sub_dir =~ /^\.|^web$|^lbin$|^log$/
      files << f
    end
    commit_results = {}
    files.each do |file|
      commit_results[file] = system("origen rc new #{file}")
    end
    commit_results.each do |file, result|
      puts "File #{file} commit result is #{result}"
    end
  end

  desc 'Find modified files'
  task :find_mods do
    puts Origen.app.rc.local_modifications.join("\n")
  end

  desc 'Commit modified files'
  task :commit_mods, [:comment] do |t, args|
    args.with_defaults(comment: 'Mass file commit, code re-factor/cleanup or lint most likely cause')
    results = `origen rc mods`.split("\n").select! { |f| f =~ /dssc diff/ }
    results.map! { |f| f[/-ver\s+\S+\s+(\S+)/, 1] }
    commit_results = {}
    results.each do |file|
      commit_results[file] = system("dssc ci -keep #{file} -com '#{args[:comment]}'")
    end
    commit_results.each do |file, result|
      puts "File #{file} commit result is #{result}"
    end
  end
end
