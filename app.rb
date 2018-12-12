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

def search_all(start = 0, size = 20)
  settings.client.search from: start, size: size
end

def search (query = nil, start = 0, size = 20)
  settings.client.search q: query, from: start, size: size
end

def paginate (start, total, page)

end

get '/organizations' do
  content_type "application/json"
  query = nil
  default_size = 20
  results = {}
  results["number of results"] = nil
  results["time taken"] = nil
  results["hits"] = []
  if params.keys.count == 0
    query = search_all
  elsif params['query']
    query = search(params['query'])
  end
  results["number of results"] = query["hits"]["total"]
  results["time taken"] = query["took"]
  query["hits"]["hits"].each { |result|
    results ["hits"] << result["_source"]
  }
  JSON.pretty_generate results
end
