require 'sinatra'
require 'json'
require 'elasticsearch'

after do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# Work around rack protection referrer bug
set :protection, :except => :json_csrf

host = ENV["ELASTIC_SEARCH"].nil? ? "http://localhost:9200" : ENV["ELASTIC_SEARCH"]

client = Elasticsearch::Client.new url: host

get '/organizations' do
  content_type :json
  default_size = 20
  results = {}
  # return everything?
  if params['query']
    query = client.search q: params['query'], size: default_size
    results["number of results"] = query["hits"]["total"]
    results["time taken"] = query["took"]
    results["hits"] = []
    query["hits"]["hits"].each { |result|
      results ["hits"] << result["_source"]
    }
    results.to_json
  end
end
