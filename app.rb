require 'sinatra'
require 'json'
require 'elasticsearch'
require 'elasticsearch/dsl'
include Elasticsearch::DSL

after do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# Work around rack protection referrer bug
set :protection, :except => :json_csrf


set :host, ENV["ELASTIC_SEARCH"].nil? ? "http://localhost:9200" : ENV["ELASTIC_SEARCH"]

set :client, Elasticsearch::Client.new, url: settings.host

set :default_size, 20

set :accepted_params, %w(query page filter query.name)

set :filter_types, %w(location type)

set :query_combinations, {:query => %w(query_string query), :query_name => {:match => {:name => ["query","operator"]}}}
def search_all(start = 0, size = settings.default_size)
  settings.client.search from: start, size: size
end

# meta program so that one can build query strings depending on parameter
# query.name is only name
#query.names looks at name, aliases, labels
# look to see how to do a filter query
# query term: {query: {match: {name: {query:"Bath Spa University",operator:"and"}}}}
def generate_query(options = {})
  q = search {
    query do
      if options.key?("query")
        query_string do
          query options["query"]
        end
      elsif options.key?("query.name")
        match :name do
          query options["query.name"]
          operator "and"
        end
      end
    end
  }
  q.to_hash
end

def process (options = {})
  msg = nil
  query = generate_query(options)
  if options["page"]
    pg = options["page"].to_i
    if (pg.is_a? Integer and pg > 0)
      msg = paginate(pg,options["query"])
    else
      msg = {:error => "page parameter: #{options['page']} must be an Integer."}
    end
  else
    binding.pry
    msg = find(query)
  end
  msg
end

def find (query = nil, start = 0, size = settings.default_size)
  if query.nil?
    search_all
  else
    settings.client.search body: query, from: start, size: size
  end
end

def search_by_id (id)
  settings.client.get_source index: 'org-id-grid', id: id
end

def paginate (page, query = nil)
    start = settings.default_size * (page - 1)
    find(query, start)
end

def check_params
  bad_param = false
  params.keys.each { |k|
    params.delete(k) unless settings.accepted_params.include?(k)
  }
end



get '/organizations' do
  content_type "application/json"
  check_params
  msg = nil
  results = {}
  errors = []
  msg = process(params)
  if msg.has_key? (:error)
    errors << msg
  else
    results["number of results"] = nil
    results["time taken"] = nil
    results["hits"] = []
    results["number of results"] = msg["hits"]["total"]
    results["time taken"] = msg["took"]
    msg["hits"]["hits"].each { |result|
      results ["hits"] << result["_source"]
    }
  end
  info = errors.empty? ? results : errors
  JSON.pretty_generate info
end

get '/organizations/:id' do
  content_type "application/json"
  msg = search_by_id(params[:id])
  JSON.pretty_generate msg
end
