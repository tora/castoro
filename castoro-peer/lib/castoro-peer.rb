
require "rubygems"

require "castoro-common"

module Castoro #:nodoc:
  module Peer #:nodoc:
    autoload :Version            , "castoro-peer/version"
    autoload :StorageSpaceMonitor, "castoro-peer/storage_space_monitor"
  end
end

