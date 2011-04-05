
require "rubygems"

require "castoro-common"

module Castoro #:nodoc:
  module Peer #:nodoc:
    autoload :Executor          , "castoro-peer/executor"
    autoload :ManipulatorError  , "castoro-peer/manipulator"
    autoload :ManipulatorService, "castoro-peer/manipulator_service"
    autoload :Version           , "castoro-peer/version"
    autoload :Workers           , "castoro-peer/workers"

    require "castoro-peer/csm_util"
  end
end

