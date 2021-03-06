# frozen_string_literal: true

module Language
  module Haskell
    module Cabal
      module Compat
        def cabal_sandbox(options = {})
          odeprecated "Language::Haskell::Cabal.cabal_sandbox"

          pwd = Pathname.pwd
          home = options[:home] || pwd

          # pretend HOME is elsewhere, so that ~/.cabal is kept as untouched
          # as possible (except for ~/.cabal/setup-exe-cache)
          # https://github.com/haskell/cabal/issues/1234
          saved_home = ENV["HOME"]
          ENV["HOME"] = home

          system "cabal", "v1-sandbox", "init"
          cabal_sandbox_bin = pwd/".cabal-sandbox/bin"
          mkdir_p cabal_sandbox_bin

          # make available any tools that will be installed in the sandbox
          saved_path = ENV["PATH"]
          ENV.prepend_path "PATH", cabal_sandbox_bin

          # avoid updating the cabal package database more than once
          system "cabal", "v1-update" unless (home/".cabal/packages").exist?

          yield

          # remove the sandbox and all build products
          rm_rf [".cabal-sandbox", "cabal.sandbox.config", "dist"]

          # avoid installing any Haskell libraries, as a matter of policy
          rm_rf lib unless options[:keep_lib]

          # restore the environment
          ENV["HOME"] = saved_home
          ENV["PATH"] = saved_path
        end

        def cabal_sandbox_add_source(*args)
          odeprecated "Language::Haskell::Cabal.cabal_sandbox_add_source"

          system "cabal", "v1-sandbox", "add-source", *args
        end

        def cabal_install(*args)
          odeprecated "Language::Haskell::Cabal.cabal_install",
                      "cabal v2-install directly with std_cabal_v2_args"

          # cabal hardcodes 64 as the maximum number of parallel jobs
          # https://github.com/Homebrew/legacy-homebrew/issues/49509
          make_jobs = (ENV.make_jobs > 64) ? 64 : ENV.make_jobs

          # cabal-install's dependency-resolution backtracking strategy can easily
          # need more than the default 2,000 maximum number of "backjumps," since
          # Hackage is a fast-moving, rolling-release target. The highest known
          # needed value by a formula at this time (February 2016) was 43,478 for
          # git-annex, so 100,000 should be enough to avoid most gratuitous
          # backjumps build failures.
          system "cabal", "v1-install", "--jobs=#{make_jobs}", "--max-backjumps=100000", *args
        end

        def cabal_configure(flags)
          odeprecated "Language::Haskell::Cabal.cabal_configure"

          system "cabal", "v1-configure", flags
        end

        def cabal_install_tools(*tools)
          odeprecated "Language::Haskell::Cabal.cabal_install_tools"

          # install tools sequentially, as some tools can depend on other tools
          tools.each { |tool| cabal_install tool }

          # unregister packages installed as dependencies for the tools, so
          # that they can't cause dependency conflicts for the main package
          rm_rf Dir[".cabal-sandbox/*packages.conf.d/"]
        end

        def install_cabal_package(*args, **options)
          odeprecated "Language::Haskell::Cabal.install_cabal_package",
                      "cabal v2-update directly followed by v2-install with std_cabal_v2_args"

          cabal_sandbox do
            cabal_install_tools(*options[:using]) if options[:using]

            # if we have build flags, we have to pass them to cabal install to resolve the necessary
            # dependencies, and call cabal configure afterwards to set the flags again for compile
            flags = "--flags=#{options[:flags].join(" ")}" if options[:flags]

            args_and_flags = args
            args_and_flags << flags unless flags.nil?

            # install dependencies in the sandbox
            cabal_install "--only-dependencies", *args_and_flags

            # call configure if build flags are set
            cabal_configure flags unless flags.nil?

            # install the main package in the destination dir
            cabal_install "--prefix=#{prefix}", *args

            yield if block_given?
          end
        end
      end

      prepend Compat
    end
  end
end
