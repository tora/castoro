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

require "castoro-peer/manipulator"

module Castoro::Peer::Manipulator #:nodoc:

  class Executor
    def initialize logger, base_dir
      @logger = logger
      @util   = CsmUtil.new base_dir

      @user  = Hash.new { |h,k| h[k] = k.kind_of?(Integer) ? Etc.getpwuid(k).uid : Etc.getpwnam(k.to_s).uid }
      @group = Hash.new { |h,k| h[k] = k.kind_of?(Integer) ? Etc.getgrgid(k).gid : Etc.getgrnam(k.to_s).gid }
    end

    def mkdir src, mode, user, group
      @logger.info { "MKDIR #{mode},#{user},#{group},#{src}" }
      m = mode.kind_of?(Fixnum) ? mode : mode.to_s.oct
      @util.mkdir src, m, @user[user], @group[group]
    end

    def move src, dst, mode, user, group
      @logger.info { "MOVE  #{mode},#{user},#{group},#{src},#{dst}" }
      m = mode.kind_of?(Fixnum) ? mode : mode.to_s.oct
      @util.move src, dst, m, @user[user], @group[group]
    end
  end

end

