require 'capistrano/ext/multistage'
require 'time'

set :keep_releases, 5
set :application,   "limecast"
set :user,          "limecast"
set :remote_home,   "/home/#{user}"
set :deploy_to,     "#{remote_home}/limecast.com"
set :use_sudo,      false

set :scm, :git
set :git_enable_submodules, 1
set :repository, "git@github.com:mnutt/limecast.git"
set :deploy_via, :copy
set :git_shallow_clone, 1
set :deploy_strategy, :export

depend :remote, :command, 'wget'
depend :remote, :command, 'git'

# Any way to reduce duplication w/ environment.rb?
depend :remote, :gem, 'mysql',           '=2.7'

# =============================================================================
# TASKS
# =============================================================================

desc "Backup database"
task :backup, :roles => :db, :only => { :primary => true } do
  filename = "/tmp/#{application}.dump.#{stage}.#{Time.now.to_f}.sql.bz2"

  # the on_rollback handler is only executed if this task is executed within
  # a transaction (see below), AND it or a subsequent task fails.
  on_rollback { delete filename }

  set :database do
    run "cd #{shared_path}; cat database.yml" do |channel, stream, data|
      @data = data
    end
    YAML::load(@data)
  end

  run "mysqldump -u limecast -p#{database['production']['password']} limecast |bzip2 -c > #{filename}" do |ch, stream, out|
    ch.send_data "#{production_database_password}\n" if out =~ /^Enter password:/
  end
  `rsync #{user}@#{domain}:#{filename} #{File.dirname(__FILE__)}/../backups/`
end

desc "Restore database"
task :restore, :roles => :db, :only => { :primary => true } do
  raise "DO NOT DROP PRODUCTION DATABASE!" if stage == "production"

  set :database do
    run "cd #{shared_path}; cat database.yml" do |channel, stream, data|
      @data = data
    end
    YAML::load(@data)
  end

  set :go_no_go do
    Capistrano::CLI.ui.ask("Are you SURE you want to drop the #{stage} database? If you want to, type \"drop #{stage} database\"")
  end
  exit(0) unless go_no_go == "drop #{stage} database"
  
  backup_path = ARGV.last.split("DB=")[1] rescue(raise ArgumentError)
  backup_file = backup_path.split('/').last
  put File.open(backup_path).read, "/tmp/#{backup_file}"

  run "cd #{latest_release}; RAILS_ENV=production rake db:drop"
  run "cd #{latest_release}; RAILS_ENV=production rake db:create"
  run "bzcat /tmp/#{backup_file} | mysql -u limecast -p#{database['production']['password']} limecast"
end

desc 'Tail the production log'
task :tail, :roles => :app do
  run "tail -f #{shared_path}/log/production.log"
end

desc "remotely console" 
task :console, :roles => :app do
  input = ''
  run "cd #{current_path} && ./script/console production" do |channel, stream, data|
    next if data.chomp == input.chomp || data.chomp == ''
    print data
    channel.send_data(input = $stdin.gets) if data =~ /^(>|\?)>/
  end
end

namespace :limecast do
  # Tasks to run after deploy
  namespace :deploy do
    desc 'Populate database with initial users and groups'
    task :populate, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake db:populate"
    end
  end

  desc "Re-generate all podcast thumbnails"
  task :refresh_thumbnails, :roles => :app do
    run "cd #{latest_release}; RAILS_ENV=production rake paperclip:refresh CLASS=Podcast"
  end

  desc "Manually update all podcast episodes"
  task :update_podcasts, :roles => :app do
    run "cd #{latest_release}; RAILS_ENV=production script/update_podcasts"
  end

  # Tasks to run after setup
  namespace :setup do
    desc 'Setup initial shared resources'
    task :default, :roles => :app do
      database_config
      create_shared
      encryption_key
      crontab
    end

    desc 'Populate a new database.yml in shared'
    task :database_config, :roles => :app do
      require 'yaml'
      set :production_database_password do
        Capistrano::CLI.password_prompt 'Production database password: '
      end

      database_config = {
        'production' => {
          'adapter'  => 'mysql',
          'database' => 'limecast',
          'username' => 'limecast',
          'password' => production_database_password,
          'host'     => 'localhost',
          'encoding' => 'utf8'
        }
      }

      put YAML::dump(database_config), "#{shared_path}/database.yml", :mode => 0664
    end

    desc 'Creates an encryption key (if necessary) and links it to config/encryption_key'
    task :encryption_key, :roles => :app do
      run "test ! -f #{shared_path}/private/encryption_key.txt || cp #{shared_path}/private/encryption_key.txt #{shared_path}/private/encryption_key.txt.1"

      # Ugh, duplication w/ Rakefile
      require 'openssl'
      encryption_key = [ OpenSSL::Random.random_bytes(60) ].pack('m*')
      put encryption_key, "#{shared_path}/private/encryption_key.txt", :mode => 0600
    end

    desc 'Creates shared directories'
    task :create_shared, :roles => :app do
      run <<-CMD
        mkdir #{shared_path}/log/sphinx &&
        mkdir #{shared_path}/sphinx &&
        mkdir #{shared_path}/vendor &&
        mkdir #{shared_path}/logos &&
        mkdir #{shared_path}/private
      CMD
    end

    desc 'Configure the crontab'
    task :crontab, :roles => :app do
      cron = <<-CRON
5,35 * * * * cd #{current_path} && RAILS_ENV=production rake ts:in
CRON
      run "rm -rf #{shared_path}/crontab"
      put cron, "#{shared_path}/crontab"
      run "crontab #{shared_path}/crontab"
    end
  end

  # Tasks to run after :update (by default, :deploy calls :update and :restart)
  namespace :update do
    desc 'Tasks to run after update'
    task :default do
      symlink_shared
      sphinx
    end

    desc 'Creates symlinks for shared resources'
    task :symlink_shared, :roles => :app do
      run <<-CMD
        rm -rf #{latest_release}/sphinx;
        rm -rf #{latest_release}/config/database.yml;
        rm -rf #{latest_release}/public/logos;
        rm -rf #{latest_release}/private;
        ln -s #{shared_path}/sphinx    #{latest_release}/sphinx &&
        ln -s #{shared_path}/database.yml   #{latest_release}/config/database.yml &&
        ln -s #{shared_path}/logos #{latest_release}/public/logos &&
        ln -s #{shared_path}/private #{latest_release}/private
      CMD
    end

    # Sphinx runs after :update, not :setup, because it depends upon the
    # project's Rakefile being present
    desc 'Builds Sphinx into shared/ (if necessary) and links it to vendor/sphinx/'
    task :sphinx, :roles => :app do
      run <<-CMD
        test -d #{shared_path}/sphinx || \
        (cd #{latest_release} && SPHINX_INSTALL_DIR=#{shared_path}/vendor/sphinx rake limecast:build_sphinx)
      CMD
      run "ln -s #{shared_path}/vendor/sphinx #{latest_release}/vendor/sphinx"
    end
  end

  # Sphinx tasks
  namespace :sphinx do
    desc 'Resets the Sphinx server -- restarts, re-configures and re-indexes'
    task :reset, :roles => :app do
      # sphinx.conf gets set with a path to the latest release -- /releases/.../.
      # The perl bit modifies it to /current/, to avoid problems.
      run <<-CMD
        cd #{latest_release} &&
        RAILS_ENV=production rake sphincter:reset &&
        cd #{shared_path}/sphinx/production &&
        perl -i -pe 's|/releases/[0-9]+?/|/current/|g' sphinx.conf
      CMD
      start
    end

    desc 'Restarts the Sphinx server'
    task :restart, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake ts:restart"
    end

    desc 'Starts the Sphinx server'
    task :start, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake ts:start"
    end

    desc 'Stops the Sphinx server'
    task :stop, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake ts:stop"
    end

    desc 'Reindexes the Sphinx server'
    task :reindex, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake ts:index"
    end

    desc 'Configures the Sphinx server'
    task :configure, :roles => :app do
      run "cd #{latest_release}; RAILS_ENV=production rake ts:config"
    end
  end

  namespace :jobs do
    desc 'Restarts the delayed_job worker'
    task :restart do
      run "cd #{latest_release}; RAILS_ENV=production rake jobs:restart"
    end

    desc 'Starts the delayed_job worker'
    task :start do
      run "cd #{latest_release}; RAILS_ENV=production rake jobs:start"
    end

    desc 'Starts the delayed_job worker'
    task :stop do
      run "cd #{latest_release}; RAILS_ENV=production rake jobs:stop"
    end
  end
end

namespace :deploy do
  desc "Restart application"
  task :restart, :roles => :app do
    run "touch #{current_path}/tmp/restart.txt"
  end

  [:start, :stop].each do |t|
    desc "#{t} task is a no-op with mod_rails"
    task t, :roles => :app do ; end
  end
end

desc "Lists all of the deployed releases by date"
task :release_times, :roles => :app do
  release_dirs = releases

  puts '=' * 40
  puts "RELEASES"
  puts '=' * 40

  release_dirs.reverse.each do |r|
    puts %{  * #{Time.parse(r.to_s).strftime("%A,\t%B %d at %I:%M%p").gsub(" 0", " ")} }
  end
end

# Override built-in deploy tasks
namespace :deploy do
  namespace :web do
    desc 'Takes the application offline with a maintenance message'
    task :disable, :roles => :web, :except => { :no_release => true } do
      require 'erb'
      on_rollback { run "rm #{shared_path}/system/maintenance.html" }

      reason = ENV['REASON']
      deadline = ENV['UNTIL']

      template = File.read('app/views/layouts/maintenance.html.erb')
      result = ERB.new(template).result(binding)

      put result, "#{shared_path}/system/maintenance.html", :mode => 0644
    end
  end
end

# =============================================================================
# EVENTS
# =============================================================================
after 'deploy:setup', 'limecast:setup'

# Run after update_code, not update since some other targets run the former.
after 'deploy:update_code', 'limecast:update'

# after 'deploy:cold', 'limecast:deploy:populate'
# after 'deploy:cold', 'limecast:sphinx:reset'

after 'deploy', 'deploy:migrate'
after 'deploy', 'limecast:sphinx:stop'
after 'deploy', 'limecast:sphinx:configure'
after 'deploy', 'limecast:sphinx:reindex'
after 'deploy', 'limecast:sphinx:reindex'
after 'deploy', 'limecast:sphinx:start'
after 'deploy', 'limecast:jobs:restart'
