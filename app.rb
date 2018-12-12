require 'sinatra'
require 'json'
require 'elasticsearch'

after do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# Work around rack protection referrer bug
set :protection, :except => :json_csrf


set :host, ENV["ELASTIC_SEARCH"].nil? ? "http://localhost:9200" : ENV["ELASTIC_SEARCH"]

set :client, Elasticsearch::Client.new, url: settings.host

set :default_size, 20

set :accepted_params, %w(query page filter)

def search_all(start = 0, size = settings.default_size)
  settings.client.search from: start, size: size
end

def process (options = {})
  msg = nil
  if options["page"]
    pg = options["page"].to_i
    if (pg.is_a? Integer and pg > 0)
      msg = paginate(pg,options["query"])
    else
      msg = {:error => "page parameter: #{options['page']} must be an Integer."}
    end
  else
    msg = search(options["query"])
  end
  msg
end

def search (query = nil, start = 0, size = settings.default_size)
  if query.nil?
    search_all
  else
    settings.client.search q: query, from: start, size: size
  end
end

def search_by_id (id)
  settings.client.get_source index: 'org-id-grid', id: id
end

def paginate (page, query = nil)
    start = settings.default_size * (page - 1)
    search(query, start)
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
