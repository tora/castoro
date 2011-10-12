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

require "monitor"

module Castoro
  class RandomCache
    PAGE_SIZE               = 32768
    DSTAT_CACHE_EXPIRE      = 1
    DSTAT_CACHE_REQUESTS    = 2
    DSTAT_CACHE_HITS        = 3
    DSTAT_CACHE_COUNT_CLEAR = 4
    DSTAT_ALLOCATE_PAGES    = 10
    DSTAT_FREE_PAGES        = 11
    DSTAT_ACTIVE_PAGES      = 12
    DSTAT_HAVE_STATUS_PEERS = 20
    DSTAT_ACTIVE_PEERS      = 21
    DSTAT_READABLE_PEERS    = 22

    attr_accessor :watchdog_limit
    attr_reader :peers

    def initialize page
      raise ArgumentError, "Page size must be > 0." unless page > 0
      @page           = page
      @watchdog_limit = 15
      @peers          = Peers.new(self)
      @finds          = 0
      @hits           = 0
    end
    def find id, type, rev
      @finds += 1
      expired = Time.now.to_i - @cache.watchdog_limit
      @peers.map { |k,v|
        if v.alive?(expired)
          v.get(id, type, rev) { |peer, base|
            make_nfs_path peer, base, id, type, rev
          }
        end
      }.compact.tap { |ret|
        @hits += 1 unless ret.empty?
      }
    end
    def stat key
      case key
        when DSTAT_CACHE_EXPIRE     ; @watchdog_limit
        when DSTAT_CACHE_REQUESTS   ; @finds
        when DSTAT_CACHE_HITS       ; @hits
        when DSTAT_CACHE_COUNT_CLEAR; (@hits * 1000 / @finds).tap { |ret| @finds = @hits = 0 }
        when DSTAT_ALLOCATE_PAGES   ; @page
        when DSTAT_FREE_PAGES       ; 0 # TODO:not implemented DSTAT_FREE_PAGES
        when DSTAT_ACTIVE_PAGES     ; 0 # TODO:nto implemented DSTAT_ACTIVE_PAGES
        when DSTAT_HAVE_STATUS_PEERS; @peers.count { |p| p.has_status? }
        when DSTAT_ACTIVE_PEERS     ; @peers.count { |p| p.writable? }
        when DSTAT_READABLE_PEERS   ; @peers.count { |p| p.readable? }
        else                        ; 0
      end
    end
    def dump io
      # TODO:not implemented #dump
    end
    def make_nfs_path peer, base, id, type, rev
      k    = id / 1000
      m, k = k.divmod 1000
      g, m = m.divmod 1000
      '%s:%s/%d/%03d/%03d/%d.%d.%d' % [peer, base, g, m, k, id, type, rev]
    end

    private

    def member_puts io, peer, base, id, type, rev
      io.puts %[  #{peer}: #{base}/#{id}.#{type}.#{rev}]
    end

    class Peers
      include Enumerable
      def initialize cache
        @cache = cache 
        @peers = Hash.new { |h,k| h[k] = Peer.new k }
      end
      def [] key
        @peers[key]
      end
      def each &block
        @peers.each &block
      end
      def find length = nil
        expired = Time.now.to_i - @cache.watchdog_limit
        @peers.select { |k,v|
          v.alive?(expired) and v.storable?(length)
        }.keys
      end
    end

    class Peer
      attr_reader :key
      def initialize key
        @key                = key
        @available          = 0
        @status             = 0
        @values             = {}
        @status_received_at = 0
      end
      def insert id, type, rev, path
        key = "#{id}:#{type}".to_sym
        @values[key] = {:rev => rev, :path => path}
      end
      def erase id, type, rev
        key = "#{id}:#{type}".to_sym
        @values.delete(key) if @values.key?(key) and @values[key][:rev] == rev
      end
      def get id, type, rev
        key = "#{id}:#{type}".to_sym
        yield(@key, @values[key][:path]) if @values.key?(key) and @values[key][:rev] == rev
      end
      def status
        {
          :available => @available,
          :status => @status,
        }
      end
      def status= status
        @available = status[:available] if status.key?(:available)
        @status    = status[:status]    if status.key?(:status)
        @status_received_at = Time.now.to_i
        status
      end
      def has_status?; @status > 0; end
      def writable?; @status >= 30; end
      def readable?; @status >= 20; end
      def storable? length
        return true unless length
        self.writable? and @available > length
      end
      def alive? expire
        @status_received_at >= expire
      end
    end
  end
end

