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

require 'castoro-peer/errors'
require 'castoro-peer/log'

require "drb/drb"

module Castoro #:nodoc:
  module Peer #:nodoc:

    class Csm
      class Client
        def initialize configurations
          @configurations   = configurations
          @unix_socket_name = @configurations[:manipulator_socket]
          @front = DRbObject.new_with_uri "drbunix://#{@unix_socket_name}"
        end

        def execute req
          req.call @front, @configurations
        rescue => e
          raise CommandExecutionError.new("CSM daemon error: #{e.message}").tap { |ex|
                  ex.set_backtrace e.backtrace
                }
        end
      end

      class Request
        def call front, conf
          @proc.call front, conf
        end
      end

      class Request::Create < Request
        def initialize path_w
          src = path_w.dup

          @proc = Proc.new { |front, config|
            mode  = config[:dir_w_perm]
            user  = config[:dir_w_user]
            group = config[:dir_w_group]

            Log.debug "CSM: MKDIR - #{mode},#{user},#{group},#{src}"
            front.mkdir src, mode, user, group
          }
        end
      end

      class Request::Delete < Request
        def initialize path_a, path_d
          src = path_a.dup
          dst = path_d.dup

          @proc = Proc.new { |front, config|
            mode  = config[:dir_d_perm]
            user  = config[:dir_d_user]
            group = config[:dir_d_group]

            Log.debug "CSM: MOVE  - #{mode},#{user},#{group},#{src},#{dst}"
            front.move src, dst, mode, user, group
          }
        end
      end

      class Request::Cancel < Request
        def initialize path_w, path_c
          src = path_w.dup
          dst = path_c.dup

          @proc = Proc.new { |front, config|
            mode  = config[:dir_c_perm]
            user  = config[:dir_c_user]
            group = config[:dir_c_group]

            Log.debug "CSM: MOVE  - #{mode},#{user},#{group},#{src},#{dst}"
            front.move src, dst, mode, user, group
          }
        end
      end

      class Request::Finalize < Request
        def initialize path_w, path_a
          src = path_w.dup
          dst = path_a.dup

          @proc = Proc.new { |front, config|
            mode  = config[:dir_a_perm]
            user  = config[:dir_a_user]
            group = config[:dir_a_group]

            Log.debug "CSM: MOVE  - #{mode},#{user},#{group},#{src},#{dst}"
            front.move src, dst, mode, user, group
          }
        end
      end

      class Request::Catch < Request
        def initialize path_r
          src = path_r.dup

          @proc = Proc.new { |front, config|
            mode  = "0755"
            user  = Process.euid
            group = Process.egid

            Log.debug "CSM: MKDIR - #{mode},#{user},#{group},#{src}"
            front.mkdir src, mode, user, group
          }
        end
      end
    end

  end
end

