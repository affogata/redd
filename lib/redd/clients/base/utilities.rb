require_relative "../../objects/base"
require_relative "../../objects/thing"
require_relative "../../objects/listing"
require_relative "../../objects/wiki_page"
require_relative "../../objects/labeled_multi"
require_relative "../../objects/more_comments"
require_relative "../../objects/comment"
require_relative "../../objects/user"
require_relative "../../objects/submission"
require_relative "../../objects/private_message"
require_relative "../../objects/subreddit"

module Redd
  module Clients
    class Base
      # Internal methods that make life easier.
      # @todo Move this out to Redd::Utils?
      module Utilities
        # The kind strings and the objects that should be used for them.
        OBJECT_KINDS = {
          "Listing"      => Objects::Listing,
          "wikipage"     => Objects::WikiPage,
          "LabeledMulti" => Objects::LabeledMulti,
          "more"         => Objects::MoreComments,
          "t1"           => Objects::Comment,
          "t2"           => Objects::User,
          "t3"           => Objects::Submission,
          "t4"           => Objects::PrivateMessage,
          "t5"           => Objects::Subreddit
        }

        # Request and create an object from the response.
        # @param [Symbol] meth The method to use.
        # @param [String] path The path to visit.
        # @param [Hash] params The data to send with the request.
        # @return [Objects::Base] The object returned from the request.
        def request_object(meth, path, params = {})
          body = send(meth, path, params).body
          object_from_body(body)
        end

        # Create an object instance with the correct attributes when given a
        # body.
        #
        # @param [Hash] body A JSON hash.
        # @return [Objects::Thing, Objects::Listing]
        def object_from_body(body)
          return nil unless body.is_a?(Hash)
          object = object_from_kind(body[:kind])
          flat = flatten_body(body)
          object.new(self, flat)
        end

        # @param [Objects::Submission, Objects::Comment] base The start of the
        #   comment tree.
        # @author Bryce Boe (@bboe) in Python
        # @return [Array<Objects::Comment, Objects::MoreComments>] A linear
        #   array of the submission's comments or the comments' replies.
        def flat_comments(base)
          meth = (base.is_a?(Objects::Submission) ? :comments : :replies)
          flatten_listing(base.send(meth))
        end

        # Fetches all accessible comments for a submission. Does an initial
        # fetch with +limit: 500+ (Reddit's max) then expands any remaining
        # {Objects::MoreComments} stubs. Accepts the same params as
        # {Objects::Submission#refresh!} (+:limit+, +:depth+, +:sort+).
        # @note Stub expansion requires an authenticated client — with
        #   {Clients::Userless}, prefer +submission.refresh!(limit: 500)+
        #   followed by {#flat_comments} to avoid a wasted API call.
        # @return [Array<Objects::Comment>]
        def fetch_all_comments(submission, **params)
          submission.refresh!(**{limit: 500}.merge(params))
          result = flat_comments(submission)

          skipped_count = 0

          loop do
            more_idx = result.index { |c| c.is_a?(Objects::MoreComments) }
            break unless more_idx

            more = result.delete_at(more_idx)
            next if more.empty? || more.id == "_"

            retries_left = 2
            begin
              expanded = submission.expand_more(more)
              result.insert(more_idx, *flatten_listing(expanded))
            rescue Redd::Error::RateLimited => e
              sleep(e.time)
              retry
            rescue Redd::Error::BadGateway,
                   Redd::Error::ServiceUnavailable,
                   Redd::Error::TimedOut
              retries_left -= 1
              if retries_left >= 0
                sleep(2)
                retry
              else
                skipped_count += more.count
              end
            rescue Redd::Error::PermissionDenied
              # 403 is auth-level — all remaining stubs will fail too, no point retrying.
              remaining_stubs = result.select { |c| c.is_a?(Objects::MoreComments) }
              skipped_count += more.count + remaining_stubs.sum(&:count)
              result.reject! { |c| c.is_a?(Objects::MoreComments) }
              break
            end
          end

          if skipped_count > 0
            warn "[redd] fetch_all_comments: #{skipped_count} comments unreachable " \
                 "(MoreComments expansion failed — 403 or transient errors after retries)"
          end

          result
        end

        # Get a given property of a given object.
        # @param [Objects::Base, String] object The object with the property.
        # @param [Symbol] property The property to get.
        def property(object, property)
          object.respond_to?(property) ? object.send(property) : object.to_s
        end

        private

        # Depth-first traversal of a listing (or any Array) of comments,
        # inlining each comment's replies in order.
        # @param [Array] listing The top-level items to traverse.
        # @return [Array<Objects::Comment, Objects::MoreComments>]
        def flatten_listing(listing)
          stack = listing.dup
          flattened = []

          until stack.empty?
            item = stack.shift
            if item.is_a?(Objects::Comment)
              replies = item.replies
              stack = replies + stack if replies
            end
            flattened << item
          end

          flattened
        end

        # Take a multilevel body ({kind: "tx", data: {...}}) and flatten it
        # into something like {kind: "tx", ...}
        # @param [Hash] body The response body.
        # @return [Hash] The flattened hash.
        def flatten_body(body)
          data = body[:data] || body
          data[:kind] = body[:kind]
          data
        end

        # @param [String] kind A kind in the format /t[1-5]/.
        # @return [Objects::Base, Objects::Listing] The appropriate object for
        #   a given kind.
        def object_from_kind(kind)
          OBJECT_KINDS.fetch(kind, Objects::Base)
        end
      end
    end
  end
end
