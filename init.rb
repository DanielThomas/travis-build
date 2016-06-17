module Travis
  module CLI
    class Fetch < RepoCommand
      description "fetches a resource from s3"

      def setup
        error "run command is not available on #{RUBY_VERSION}" if RUBY_VERSION < '1.9.3'
        $:.unshift File.expand_path('../lib', __FILE__)
        require 'travis/build'
      end

      def run(*arg)
        cache_options = {
          fetch_timeout: 20,
          push_timeout: 30,
          type: 's3',
          s3: {
            :scheme => 'http',
            :bucket => ENV['AWS_S3_BUCKET'],
            :access_key_id => ENV['AWS_ACCESS_KEY_ID'],
            :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'],
            :token => ENV['AWS_SESSION_TOKEN']
          }
        }
        payload = {
          'type' => 'test',
          'config' => {
            'os' => 'linux',
            'env' => ['FOO=foo', 'SECURE BAR=bar']
          },
          'repository' => {
            'github_id' => 'niagara',
            'slug' => 'travis-ci/travis-ci',
            'source_url' => 'git://github.com/travis-ci/travis-ci.git'
          },
          'build' => {
            'id' => '1',
            'number' => '1',
            'previous_state' => 'failed'
          },
          'job' => {
            'id' => '1',
            'number' => '1.1',
            'commit' => '313f61b',
            'branch' => 'master',
            'commit_range' => '313f61b..313f61a',
            'commit_message' => 'the commit message',
            'secure_env_enabled' => true
          }
        }
        data = payload.deep_merge(config: {}, cache_options: cache_options, job: { branch: "master", pull_request: nil })
        sh = Travis::Shell::Builder.new
        directory_cache = Travis::Build::Script::DirectoryCache.const_get("S3").new(sh, Travis::Build::Data.new(data), "test", Time.now)
        puts directory_cache.fetch_url
      end
    end

    class Compile < RepoCommand
      description "compiles a build script from .travis.yml"

      attr_accessor :slug, :source_url

      def setup
        error "run command is not available on #{RUBY_VERSION}" if RUBY_VERSION < '1.9.3'
        $:.unshift File.expand_path('../lib', __FILE__)
        require 'travis/build'
      end

      def find_source_url
          git_head    = `git name-rev --name-only HEAD 2>#{IO::NULL}`.chomp
          git_remote  = `git config --get branch.#{git_head}.remote 2>#{IO::NULL}`.chomp
          return `git ls-remote --get-url #{git_remote} 2>#{IO::NULL}`.chomp
      end

      def run(*arg)
        @slug = find_slug
        @source_url = find_source_url
        if match_data = /\A(?<build>\d+)(\.(?<job>\d+))?\z/.match(arg.first)
          set_up_config(match_data)
        elsif arg.length > 0
          warn "#{arg.first} does not look like a job number. Last build's first job is assumed."
          @config = last_build.jobs[0].config
        else
          ## No arg case; use .travis.yml from $PWD
          config = travis_config

          global_env = sanitize_global_env(config)

          if config.has_key? 'matrix'
            warn 'matrix key is ignored'
            config.delete_if { |k,v| k == 'matrix' }
          end

          if config['os'] && ! config['os'].respond_to?(:scan)
            warn "'os' key is unsupported in local build script compilation. Setting to default, 'linux'."
            config['os'] = 'linux'
          end

          set_up_env(config, global_env)
        end

        puts Travis::Build.script(push_down_deploy(@config)).compile(true)
      end

      private
        def data
          {
            :config => @config,
            :repository => {
              :slug => slug,
              :source_url => source_url,
              :github_id => 1234567890
            },
            :cache_options => {
              :type => :s3,
              :s3 => {
                :bucket => 'cache_bucket',
                :access_key_id => 'abcdef0123456789',
                :secret_access_key => 'super_duper_secret'
              },
              :fetch_timeout => 60,
              :push_timeout => 60
            }
          }
        end

        def set_up_config(match_data)
          @build = build(match_data[:build])
          @job_number = match_data[:job].to_i - 1
          @config = @build.jobs[@job_number].config
        end

        def sanitize_global_env(config)
          global_env = []
          if config.has_key? 'env'
            case config['env']
            when Hash
              if config['env']['matrix']
                warn 'env.matrix key is ignored'
              end
              global_env = config['env'].fetch('global', [])
              global_env.delete_if { |v| v.is_a? Hash }
            when Array
              global_env = config['env']
            end
          end

          global_env
        end

        def set_up_env(config, global_env)
          @config = config.delete_if {|k,v| k == 'env' }
          @config['env'] = global_env
        end

        def push_down_deploy(config)
          if deploy_data = config.delete('deploy')
            addons_data = config.fetch('addons', {})
            config['addons'] = addons_data.merge({'deploy' => deploy_data})
          end
          data
        end
    end
  end
end
