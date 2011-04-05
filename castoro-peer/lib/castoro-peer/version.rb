
module Castoro #:nodoc:
  module Peer #:nodoc:
    module Version #:nodoc:
      unless defined? MAJOR
        MAJOR  = 0
        MINOR  = 2
        TINY   = 0
        PRE    = nil

        STRING = [MAJOR, MINOR, TINY, PRE].compact.join('.')

        PROGRAM_VERSION = "peer-#{STRING} - 2011-03-30"
      end
    end
  end
end

