
require "rubygems"

require "castoro-common"

module Castoro #:nodoc:
  module Peer #:nodoc:
    module Manipulator #:nodoc:
      autoload :Service         , "castoro-peer/manipulator/service"
      autoload :Executor        , "castoro-peer/manipulator/executor"
      autoload :ManipulatorError, "castoro-peer/manipulator/service"

      require "castoro-peer/manipulator/csm_util.so"
    end
  end
end

