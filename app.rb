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

set :accepted_params, %w(query page filter query.name query.names)

set :filter_types, %w(location type)

set :accepted_param_values, %w(location types)

def search_all(start = 0, size = settings.default_size)
  settings.client.search from: start, size: size
end

def simple_query(term)
  query_string do
    query term
  end
end

def match_field(field, term)
  match field.to_sym do
    query term
    operator "and"
  end
end

def multi_field_match(fields, term)
  multi_match do
    query    term
    operator 'and'
    fields   fields
  end
end

# filter=types:blah,country.country_code, country.country_name
def gen_filtered_query(filter_query_array)
  query_type = filter_query_array.size > 1 ? {} : []
  if filter_query_array.count > 1
    query_type = []
    filter_query.each { |f|
      field,term = f.split(":")
      query_type << match_field(field,term)
    }
  else
    query_type = {}
    field,term = filter_query_array[0].split(":")
    binding.pry
    query_type = match_field(field,term)
  end
  filter do
    query_type
  end
end

def gen_bool_query(query_type,filter_type)
  query_type = filter_query_array.size > 1 ? {} : []
  bool do
    must do
      query_type
    end
    filter do
    end
  end
end
# meta program so that one can build query strings depending on parameter
# query.name is only name
#query.names looks at name, aliases, labels
# look to see how to do a filter query
# query term: {query: {match: {name: {query:"Bath Spa University",operator:"and"}}}}
# create query strings by parameter
def generate_query(options = {})
  filter = nil
  qt = nil
  if options["filter"]
    filter = options["filter"].split(",")
  end
  q = search {
    query do
      if options.key?("query")
        qt = simple_query(options["query"])
      elsif options.key?("query.name")
        qt = match_field("name",options["query.name"])
      elsif options.key?("query.names")
        fields = %w[ name aliases acronyms labels.label ]
        qt = multi_field_match(fields, options["query.names"])
      end
      gen_bool_query(qt,filter) if filter
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
      msg = paginate(pg,query)
    else
      msg = {:error => "page parameter: #{options['page']} must be an Integer."}
    end
  else
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
