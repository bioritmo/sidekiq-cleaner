require 'uri'

module Sidekiq
  module Cleaner
    module WebExtension
      def self.registered(app)
        view_path = File.join(File.expand_path("..", __FILE__), "views")

        app.post "/cleaner" do
          throw :halt, 404 unless params['key']
          params['key'].each do |key|
            job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
            if job
              if params['retry']
                job.retry
              elsif params['delete']
                job.delete
              end
            end
          end

          redirect URI.parse(request.referer).path
        end

        app.post "/cleaner/:key" do
          throw :halt, 404 unless params['key']

          job = Sidekiq::DeadSet.new.fetch(*parse_params(params['key'])).first
          if job
            if params['retry']
              job.retry
            elsif params['delete']
              job.delete
            end
          end

          redirect URI.parse(request.referer).path
        end

        app.post "/cleaner/:failure_class/:error_class/:bucket_name/delete" do
          @dead,
          @req_failure_class,
          @req_bucket_name,
          @req_error_class = Sidekiq::Cleaner::JobFilter.filter_dead_jobs_by_params(params)

          @dead.each do |dead_job|
            dead_job['job'].delete
          end

          redirect URI.parse(request.url.split("/")[0..-2].join("/")).path # Redirect back to the original url
        end

        app.post "/cleaner/:failure_class/:error_class/:bucket_name/retry" do
          @dead,
          @req_failure_class,
          @req_bucket_name,
          @req_error_class = Sidekiq::Cleaner::JobFilter.filter_dead_jobs_by_params(params)
          Sidekiq::SortedEntry
          @dead.each do |dead_job|
            dead_job['job'].retry
          end

          redirect URI.parse(request.url.split("/")[0..-2].join("/")).path # Redirect back to the original url
        end

        app.get "/cleaner/:failure_class/:error_class/:bucket_name" do
          @dead,
          @req_failure_class,
          @req_bucket_name,
          @req_error_class = Sidekiq::Cleaner::JobFilter.filter_dead_jobs_by_params(params)

          # Display dead jobs as list
          @dead = @dead.map { |obj| obj["job"] }

          @cleaner_path = "cleaner/#{@req_failure_class}/#{@req_error_class}/#{@req_bucket_name}"

          # Pagination
          @total_size = @dead.size
          @current_page = params[:page] || 1
          @current_page = @current_page.to_i
          @count = 50 # per page
          @dead = @dead[((@current_page-1) * @count) , @count]


          # Remove unrelated arguments to allow _paginate url to be clean
          # Hack to continue to reuse sidekiq's _pagination template
          params.delete("failure_class")
          params.delete("bucket_name")
          params.delete("error_class")


          render(:erb, File.read(File.join(view_path, "cleaner_failures.erb")))
        end

        app.get "/cleaner/:failure_class/:bucket_name" do
          @dead,
          @req_failure_class,
          @req_bucket_name,
          @req_error_class = Sidekiq::Cleaner::JobFilter.filter_dead_jobs_by_params(params)

          @cleaner_path = "cleaner/#{@req_failure_class}"
          @failure_link = '/total_failures'

          @total_dead = @dead.size
          @count_by_class = Sidekiq::Cleaner::JobAggregator.group_by(@dead, 'error_class', 'bucket_name')
          @count_by_class = @count_by_class.collect { |k, v| [k, v] }.sort{|x, y| x[1]['total_failures'] <=> y[1]['total_failures'] }.reverse
          render(:erb, File.read(File.join(view_path, "cleaner.erb")))
        end

        app.get "/cleaner" do
          @dead,
          @req_failure_class,
          @req_bucket_name,
          @req_error_class = Sidekiq::Cleaner::JobFilter.filter_dead_jobs_by_params(params)

          @cleaner_path = "cleaner"
          @failure_link = '/AllErrors/total_failures'

          @total_dead = @dead.size
          @count_by_class = Sidekiq::Cleaner::JobAggregator.group_by(@dead, 'failure_class', 'bucket_name')
          @count_by_class = @count_by_class.collect { |k, v| [k, v] }.sort{|x, y| x[1]['total_failures'] <=> y[1]['total_failures'] }.reverse
          render(:erb, File.read(File.join(view_path, "cleaner.erb")))
        end

      end
    end
  end
end
