module Redd
  module Objects
    # The model for a morecomments object
    class MoreComments < Array
      # @return [String] The id of this stub. Reddit uses "_" for
      #   "continue this thread" stubs that cannot be expanded via the API.
      attr_reader :id

      # @return [Integer] The number of hidden comments Reddit reports behind
      #   this stub. May exceed the actual number of retrievable IDs in the
      #   children array.
      attr_reader :count

      def initialize(_, attributes)
        @id = attributes[:id]
        @count = attributes[:count].to_i
        #Return an empty array if there are no children
        super(attributes[:children]) if attributes[:children]
      end
    end
  end
end
