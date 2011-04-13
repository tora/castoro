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

require "logger"
require "sync"
require "drb/drb"

module Castoro
  class ServerError < CastoroError; end

  class Gateway

    class ConsoleServer

      @@forker = Proc.new { |*args, &block|
        fork {
          exit! 0 if fork {
            block.call(*args)
          }
        }
        Process.wait
      }

      DEFAULT_SETTINGS = {
        :host => nil,
      }

      ##
      # initialize.
      #
      # === Args
      #
      # +logger+::
      #   the logger.
      # +repository+::
      #   the repository instance.
      # +port+::
      #   port number of TCP Socket.
      # +options+::
      #   server options.
      #
      # Valid options for +options+ are:
      #
      #   [:host]             allow hosts.
      #
      def initialize logger, repository, port, options = {}
        raise ServerError, "zero and negative number cannot be set to port." if port.to_i <= 0

        @logger     = logger || Logger.new(nil)
        @repository = repository
        @port       = port.to_i

        options.reject! { |k, v| !(DEFAULT_SETTINGS.keys.include? k.to_sym)}
        DEFAULT_SETTINGS.merge(options).each { |k, v|
          instance_variable_set "@#{k}", v
        }
        @uri = "druby://#{@host}:#{@port}"

        @locker = Sync.new
      end

      def start
        @locker.synchronize(:EX) {
          raise ServerError, "console already started." if alive?

          DRb.start_service(@uri, self)
          @alive = true

          self
        }
      end

      def stop
        @locker.synchronize(:EX) {
          raise ServerError, "console already stopped." unless alive?

          DRb.stop_service
          @alive = false

          self
        }
      end

      def alive?; @locker.synchronize(:SH) { !! @alive }; end

      def peers
        raise ServerError, "console has not started yet." unless alive?
        @repository.peers
      end

      def status
        raise ServerError, "console has not started yet." unless alive?
        @repository.status
      end

      def dump &block
        raise ServerError, "console has not started yet." unless alive?

        TCPServer.open(0) { |serv|
          port = serv.addr[1]

          Thread.fork(port) { |port|
            serv.accept.tap { |cli|
              begin
                while (buf = cli.gets); yield buf; end
              ensure
                cli.close rescue nil
              end
            }

          }.tap { |t|
            begin
              @@forker.call(port) { |port|
                TCPSocket.open(nil, port) { |s|
                  @repository.dump s
                }
              }

            ensure
              t.join
            end
          }
        }
      end
    end

  end
end

