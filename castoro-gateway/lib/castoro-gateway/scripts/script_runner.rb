#
#   Copyright 2010 Ricoh Company, Ltd.
#
#   This file is part of Castoro.
#
#   Castoro is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   Castoro is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with Castoro.  If not, see <http://www.gnu.org/licenses/>.
#

require "castoro-gateway"

require "erb"
require "logger"
require "yaml"
require "fileutils"
require "timeout"
require "etc"

module Castoro
  class ScriptRunner
    @@stop_timeout = 10

    def self.start options
      puts "*** Starting Castoro::Gateway..."

      config = YAML::load(ERB.new(IO.read(options[:conf])).result)

      raise "Environment not found - #{options[:env]}" unless config.include?(options[:env])
      config = config[options[:env]]

      user = config["user"] || Castoro::Gateway::DEFAULT_SETTINGS["user"]
      
      uid = begin
              user.kind_of?(Integer) ? Etc.getpwuid(user.to_i).uid : Etc.getpwnam(user.to_s).uid 
            rescue ArgumentError
              raise "can't find user for #{user}"
            end

      raise "Dont't run as root user." if uid == 0

      Process::Sys.seteuid(uid)

      if options[:daemon]
        raise "PID file already exists - #{options[:pid]}" if File.exist?(options[:pid])

        logdir = File.dirname(options[:log])
        FileUtils.mkdir_p logdir unless File.directory?(logdir)
        FileUtils.touch options[:log]

        piddir = File.dirname(options[:pid])
        FileUtils.mkdir_p piddir unless File.directory?(piddir)
        FileUtils.touch options[:pid]

        fork {
          Process.setsid
          fork {
            Dir.chdir("/")
            File.umask(0)
            STDIN.reopen  "/dev/null", "r+"
            STDOUT.reopen options[:log], "a"; STDOUT.sync = true
            STDERR.reopen options[:log], "a"; STDERR.sync = true

            init_gateway config, options[:pid]
            sleep
          }
        }
      else
        init_gateway config
      end

    rescue => e
      puts "--- Castor::Gateway error! - #{e.message}"
      puts e.backtrace.join("\n\t") if options[:verbose]
      exit(1)

    ensure
      puts "*** done."
    end

    def self.stop options
      puts "*** Stopping Castor::Gateway daemon..."
      raise "PID file not found - #{options[:pid]}" unless File.exist?(options[:pid])
      timeout(@@stop_timeout) {
        send_signal(options[:pid], options[:force] ? :TERM : :HUP)
        while File.exist?(options[:pid]) ; end
      }

    rescue => e
      puts "--- Castor::Gateway error! - #{e.message}"
      puts e.backtrace.join("\n\t") if options[:verbose]
      exit(1)
      
    ensure
      puts "*** done."
    end

    def self.setup options
      puts "*** Stopping Castor::Gateway daemon..."
      puts "--- setup configuration file to #{options[:conf]}..."

      if File.exist?(options[:conf])
        raise "Config file already exists - #{options[:conf]}" unless options[:force]
      end

      confdir = File.dirname(options[:conf])
      FileUtils.mkdir_p confdir unless File.directory?(confdir)
      open(options[:conf], "w") { |f|
        f.puts Castoro::Gateway::SETTING_TEMPLATE
      }
      
    rescue => e
      puts "--- Castor::Gateway error! - #{e.message}"
      puts e.backtrace.join("\n\t") if options[:verbose]
      exit(1)

    ensure
      puts "*** done."
    end

    def self.status options
      port = options[:port].to_i

      ret = Castoro::Sender::TCP.start(Logger.new(nil), "127.0.0.1", port, 3.0) { |s|
        s.send(Castoro::Protocol::Command::Status.new, 3.0)
      }

      width  = ret.keys.max { |x, y| x.length <=> y.length }.length
      key_format = "%-#{width}s"
      ret.each { |k, v|
        puts "#{key_format % k} : #{v}"
      }
    rescue => e
      puts "--- Castor::Gateway error! - #{e.message}"
      puts e.backtrace.join("\n\t") if options[:verbose]
      exit(1)
    end

    private

    def self.init_gateway config, pid_file = nil
      logger = Logger.new(STDOUT)
      gateway = Gateway.new(config, logger)

      # signal.
      stopping = false
      [:INT, :HUP, :TERM].each { |sig|
        trap(sig) { |s|
          unless stopping
            stopping = true
            gateway.stop (s == :TERM)
            FileUtils.rm pid_file if pid_file and File.exist? pid_file
            exit! 0
          end
        }
      }

      # start gateway.
      gateway.start

      # write pid to file.
      File.open(pid_file, "w") { |f| f.puts $$ } if pid_file

      # sleep.
      while gateway.alive?; sleep 3; end
    end

    def self.send_signal pid_file, signal
      # SIGINT signal is sent to dispatcher deamon(s).
      pid = File.open(pid_file, "r") do |f|
        f.read
      end.to_i

      Process.kill(signal, pid)
      Process.waitpid2(pid) rescue nil
    end
  end
end