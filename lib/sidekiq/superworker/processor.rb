module Sidekiq
  module Superworker
    class Processor
      def complete(item, new_thread=true)
        Superworker.debug "JID ##{item['jid']}: Sidekiq job complete"
        if new_thread
          # Run this in a new thread so that its execution isn't considered to be part of the
          # completed job's execution.
          Thread.new do
            complete_item(item)
          end
        else
          complete_item(item)
        end
      end

      def error(worker, item, queue, exception)
        raise "Job has nil jid: #{item}" if item['jid'].nil?

        Superworker.debug "JID ##{item['jid']}: Error thrown"
        subjob = find_subjob_by_jid(item['jid'])
        SubjobProcessor.error(subjob, worker, item, exception) if subjob
      end

      protected

      def complete_item(item)
        raise "Job has nil jid: #{item}" if item['jid'].nil?

        Superworker.debug "JID ##{item['jid']}: Passing job from Sidekiq to Superworker"
        subjob = find_subjob_by_jid(item['jid'])
        SubjobProcessor.complete(subjob) if subjob
      end

      # Note: The job may've been created outside of sidekiq-superworker, so a nil return value
      # for this method isn't necessarily problematic
      def find_subjob_by_jid(jid)
        Superworker.debug "JID ##{jid}: Trying to find Subjob"
        # The job may complete before the Subjob record is created; in case that happens,
        # we need to sleep briefly and requery.
        tries = 5
        subjob = nil
        (1..tries).each do |try|
          subjob = Subjob.find_by_jid(jid)
          break if subjob
          Superworker.debug "JID ##{jid}: Sleeping before trying to find Subjob again"
          sleep (2 ** try)
        end
        Superworker.debug "JID ##{jid}: Subjob found: #{subjob ? subjob.to_info : 'nil'}"
        subjob
      end
    end
  end
end
