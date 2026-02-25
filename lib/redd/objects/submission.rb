require_relative "thing"

module Redd
  module Objects
    # A submission made in a subreddit.
    class Submission < Thing
      include Thing::Editable
      include Thing::Hideable
      include Thing::Moderatable
      include Thing::Refreshable
      include Thing::Saveable
      include Thing::Votable

      alias_property :nsfw?, :over_18
      alias_property :self?, :is_self
      alias_property :comments_count, :num_comments

      # The shorter url for sharing.
      def short_url
        "http://redd.it/#{self[:id]}"
      end

      # Whether the comment was gilded.
      def gilded?
        self[:gilded] > 0
      end

      # Mark the thing as Not Suitable For Work.
      def mark_as_nsfw
        get("/api/marknsfw", id: fullname)
        self[:over_18] = true
      end

      # No longer mark the thing as Not Suitable For Work.
      def unmark_as_nsfw
        get("/api/unmarknsfw", id: fullname)
        self[:over_18] = false
      end
      alias_method :mark_as_safe, :unmark_as_nsfw

      # Reply to the thing.
      # @param text [String] The text to comment.
      # @return [Objects::Comment] The reply.
      def add_comment(text)
        client.add_comment(self, text)
      end

      # Set the submission to "contest mode" (comments are randomly sorted)
      def set_contest_mode
        post("/api/set_contest_mode", id: fullname, state: true)
      end

      # Unset the "contest mode".
      def unset_contest_mode
        post("/api/set_contest_mode", id: fullname, state: false)
      end

      # Set the submission as the sticky post of the subreddit
      def set_sticky
        post("/api/set_subreddit_sticky", id: fullname, state: true)
        self[:stickied] = true
      end

      # Unsticky the post from the subreddit
      def unset_sticky
        post("/api/set_subreddit_sticky", id: fullname, state: false)
        self[:stickied] = false
      end

      # @param params [Hash] Optional params forwarded to the API.
      # @option params [1..500] :limit Maximum number of top-level comments to
      #   return (Reddit caps this at 500).
      # @option params [Integer] :depth Maximum depth of subtrees in the
      #   thread.
      # @option params [:confidence, :top, :new, :controversial, :old,
      #   :random, :qa] :sort Comment sort order.
      # @return [Listing] The submission's comments.
      def comments(**params)
        refresh!(**params) if !@comments || !params.empty?
        @comments
      end
      alias_method :replies, :comments

      # Refresh the submission AND its comments.
      # @param params [Hash] Optional params forwarded to the API (see
      #   {#comments} for supported options).
      # @return [Submission] The updated submission.
      def refresh!(**params)
        body = get("/comments/#{id}.json", params).body
        @comments = client.object_from_body(body[1])
        deep_merge!(body[0])
      end

      # Take a MoreComments and return a listing of comments.
      # @param [MoreComments] more The object to expand.
      # @return [Listing] A listing of the expanded comments.
      # @note Reddit's /api/morechildren silently truncates large requests, so
      #   children are fetched in batches of {MORECHILDREN_BATCH_SIZE}.
      MORECHILDREN_BATCH_SIZE = 20

      def expand_more(more)
        things = more.each_slice(MORECHILDREN_BATCH_SIZE).flat_map do |batch|
          response = client.get(
            "/api/morechildren",
            children: batch.join(","),
            link_id: fullname
          )
          response.body[:json][:data][:things]
        end

        client.object_from_body(
          kind: "Listing",
          data: {before: "", after: "", children: things}
        )
      end

      # Get the related articles.
      # @param [Hash] params A list of params to send with the request.
      # @option params [String] :after Return results after the given
      #   fullname.
      # @option params [String] :before Return results before the given
      #   fullname.
      # @option params [Integer] :count The number of items already seen
      #   in the listing.
      # @option params [1..100] :limit The maximum number of things to
      #   return.
      # @return [Objects::Listing<Objects::Thing>]
      def get_related(**params)
        related = get("/related/#{id}.json", params).body[1]
        client.object_from_body(related)
      end

      # Get other articles with the same URL.
      # @param [Hash] params A list of params to send with the request.
      # @option params [String] :after Return results after the given
      #   fullname.
      # @option params [String] :before Return results before the given
      #   fullname.
      # @option params [Integer] :count The number of items already seen
      #   in the listing.
      # @option params [1..100] :limit The maximum number of things to
      #   return.
      # @return [Objects::Listing<Objects::Submission>]
      def get_duplicates(**params)
        duplicates = get("/duplicates/#{id}.json", params).body[1]
        client.object_from_body(duplicates)
      end
    end
  end
end
