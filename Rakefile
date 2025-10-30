require 'bundler'

BUNDLE_BIN = Bundler.bundle_path.join('bin', 'bundle')
desc 'execute llmed'
task :llmed, :source do |_, args|
  sh "#{BUNDLE_BIN} exec ruby -W -I./lib exe/llmed #{args.source}"
end

desc 'execute llmed.literate'
task :"llmed.literate", :source do |_, args|
  sh "#{BUNDLE_BIN} exec ruby -W -I./lib exe/llmed.literate #{args.source}"
end
