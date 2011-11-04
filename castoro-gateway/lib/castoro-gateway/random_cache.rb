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

require "forwardable"
require "monitor"
require 'kyotocabinet'
require 'msgpack'

module Castoro

  ##
  # Substitutes for cache made by C++
  #
  # It is having structure strong against random access. 
  # However, there is much memory usage and its space efficiency is bad. 
  #
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

    ##
    # Initialize.
    #
    # === Args
    #
    # +size+:: cache size
    #
    def initialize size
      raise ArgumentError, "Cache size must be > 0." unless size > 0
      @watchdog_limit = 15
      @map            = Map.new(size)
      @peers          = Peers.new(self, @map)
      @finds          = 0
      @hits           = 0
    end

    ##
    # A cache element is searched.
    #
    # The arrangement of the NFS path of an object element is returned. 
    #
    # === Args
    #
    # +id+    :: Basket Id
    # +type+  :: Basket Type
    # +rev+   :: Basket Revision
    #
    def find id, type, rev
      @finds += 1
      expired = Time.now.to_i - @watchdog_limit
      (@map.get(id, type, rev) || {}).map { |kv|
        peer, base = kv.map { |x| ObjectSpace._id2ref(x) }
        make_nfs_path(peer, base, id, type, rev) if @peers[peer].alive?(expired)
      }.compact.tap { |ret|
        @hits += 1 unless ret.empty?
      }
    end

    ##
    # cache status is returned.
    #
    # === Args
    #
    # +key+ :: status key
    #
    def stat key
      case key
        when DSTAT_CACHE_EXPIRE     ; @watchdog_limit
        when DSTAT_CACHE_REQUESTS   ; @finds
        when DSTAT_CACHE_HITS       ; @hits
        when DSTAT_CACHE_COUNT_CLEAR; (@finds == 0 ? 0 : @hits * 1000 / @finds).tap { |ret| @finds = @hits = 0 }
        when DSTAT_ALLOCATE_PAGES   ; 0 # In RandomCache There is no concept of a page segment. 
        when DSTAT_FREE_PAGES       ; 0 # In RandomCache There is no concept of a page segment. 
        when DSTAT_ACTIVE_PAGES     ; 0 # In RandomCache There is no concept of a page segment. 
        when DSTAT_HAVE_STATUS_PEERS; @peers.count { |k,v| v.has_status? }
        when DSTAT_ACTIVE_PEERS     ; @peers.count { |k,v| v.writable? }
        when DSTAT_READABLE_PEERS   ; @peers.count { |k,v| v.readable? }
        else                        ; 0
      end
    end

    ##
    # Cache information is dumped.
    #
    # === Args
    #
    # +io+ :: the IO Object 
    #
    def dump io
      @map.each { |id, type, rev, peer, base|
        member_puts io, peer, base, id, type, rev
      }
    end

    ##
    # A nfs path is constituted.
    #
    # === Args
    #
    # +peer+  :: peer id
    # +base+  :: base path
    # +id+    :: Basket Id
    # +type+  :: Basket Type
    # +rev+   :: Basket Revision
    #
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

    ##
    # Set of Peer
    #
    class Peers
      extend Forwardable
      include Enumerable

      def_delegators :@peers, :each, :delete

      ##
      # Initialize.
      #
      # === Args
      #
      # +cache+ :: RandomCache instance.
      # +map+   :: k-v store map instance.
      #
      def initialize cache, map
        @cache = cache
        @map   = map
        @peers = Hash.new { |h,k| h[k] = Peer.new(@cache, @map, self, k) }
      end

      ##
      # The reference to Peer is returned.
      #
      def [] key
        @peers[key.to_sym]
      end

      ##
      # storable peer is returned.
      #
      # === Args
      #
      # +length+:: required size.
      #
      def find length = nil
        expired = Time.now.to_i - @cache.watchdog_limit
        @peers.select { |k,v| v.alive?(expired) and v.storable?(length) }.keys.map(&:to_s)
      end
    end

    ##
    # The class expressing Peer.
    #
    class Peer

      ##
      # Initialize
      #
      # === Args
      #
      # +cache+ :: RandomCache instance.
      # +map+   :: k-v store map instance.
      # +peers+ :: Peers instance
      # +key+   :: Peer ID
      #
      def initialize cache, map, peers, key
        @cache              = cache
        @map                = map
        @peers              = peers
        @key                = key.to_sym.object_id
        @available          = 0
        @status             = 0
        @values             = {}
        @status_received_at = 0
      end

      ##
      # The element belonging to Peer is added.
      #
      # === Args
      #
      # +id+    :: Basket Id
      # +type+  :: Basket Type
      # +rev+   :: Basket Revision
      # +path+  :: Basket base path.
      #
      def insert id, type, rev, path
        if (peers = @map.get id, type, rev)
          peers[@key] = path.to_sym.object_id
          @map.set id, type, rev, peers
        else
          @map.set id, type, rev, @key => path.to_sym.object_id
        end
      end

      ##
      # The element belonging to Peer is deleted.
      #
      # === Args
      #
      # +id+    :: Basket Id
      # +type+  :: Basket Type
      # +rev+   :: Basket Revision
      #
      def erase id, type, rev
        if (peers = @map.get id, type, rev)
          peers.delete(@key)
          @map.set id, type, rev, peers
        end
      end

      ##
      # Peer status is returned.
      #
      # see #status=
      #
      def status
        {
          :available => @available,
          :status => @status,
        }
      end

      ##
      # Setter of status.
      #
      # === Args
      #
      # +status+::
      #   Hash expressing status
      #
      # === status details
      #
      # Acceptance of the following key values is possible. 
      #
      # +:available+  :: storable capacity.
      # +:status+     :: status code.
      #
      def status= status
        @available = status[:available] if status.key?(:available)
        @status    = status[:status]    if status.key?(:status)
        @status_received_at = Time.now.to_i
        status
      end

      ##
      # Remove Peer.
      #
      def remove
        @peers.delete(ObjectSpace._id2ref(@key))
      end

      ##
      # It is returned whether has status or not. 
      #
      def has_status?; @status > 0; end

      ##
      # It is returned whether writing is possible.
      #
      def writable?; @status >= 30; end

      ##
      # It is returned whether reading is possible.
      #
      def readable?; @status >= 20; end

      ##
      # It is returned whether new Basket is storable. 
      #
      def storable? length
        return true unless length
        self.writable? and @available > length
      end

      ##
      # It is returned whether has vital reaction or not.
      # 
      # === Args
      #
      # +expire+::
      #   expiration time
      #
      def alive? expire
        @status_received_at >= expire
      end
    end

    ##
    # Key-Value Store which considered BasketRevision.
    #
    class Map
      ##
      # Initialize.
      #
      # === Args
      #
      # +size+::
      #   cache size.
      #
      def initialize size
        @db = KyotoCabinet::DB.new
        @db.open("*#capsiz=#{size}")
      end

      ##
      # get value.
      #
      # Hash of peer-path pair is returned.
      #
      # === Args
      #
      # +id+::
      #   BasketId
      # +type+::
      #   BasketType
      # +rev+::
      #   BasketRevision
      #
      def get id, type, rev
        k, r = to_keys id, type, rev
        return nil unless (val = @db.get(k))
        val = MessagePack.unpack(val)
        return nil unless val['rev'] == r
        val['peers']
      end

      ##
      # set value.
      #
      # === Args
      #
      # +id+::
      #   BasketId
      # +type+::
      #   BasketType
      # +rev+::
      #   BasketRevision
      # +peers+::
      #   Hash of peer-path pair
      #
      def set id, type, rev, peers
        k, r = to_keys id, type, rev
        if (peers || {}).empty?
          @db.remove(k)
        else
          @db.set(k, {'rev' => r, 'peers' => peers}.to_msgpack)
        end
        peers
      end

      ##
      # #each
      #
      # Block receives 5 arguments.
      #
      # == Block arguments
      #
      # +id+::
      #   BasketId
      # +type+::
      #   BasketType
      # +rev+::
      #   BasketRevision
      # +peer+::
      #   Peer ID
      # +base+::
      #   stored path for peer
      #
      def each
        @db.each { |kv|
          k, v = kv.map { |r| MessagePack.unpack(r) }
          id, type = k.to_s.split(':', 2)
          rev      = v['rev']
          peers    = v['peers']
          peers.each { |pb|
            peer, base = pb.map { |x| ObjectSpace._id2ref(x) }
            yield [id, type, rev, peer, base]
          }
        }
        self
      end

      private

      def to_keys id, type, rev
        ["#{id}:#{type}".to_msgpack, rev & 255]
      end

    end
  end
end

