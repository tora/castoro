
require "rubygems"

require "castoro-common"
require "castoro-peer"

module Castoro::Peer::Core #:nodoc:
  require "castoro-peer/core/console"
  require "castoro-peer/core/facade"
  require "castoro-peer/core/generator"
  require "castoro-peer/core/publisher"
  require "castoro-peer/core/service"
  require "castoro-peer/core/storage_monitor"
  require "castoro-peer/core/watchdog"
  require "castoro-peer/core/workers"
end

