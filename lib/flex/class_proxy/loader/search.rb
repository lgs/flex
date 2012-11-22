module Flex
  module ClassProxy
    module Loader
      module Search

        def define_search(name, source, source_vars=nil)
          structure = Utils.data_from_source(source)
          structure = [structure] unless structure.is_a?(Array)
          send :define_template, Template::Search, name, structure, source_vars
        end

        # http://www.elasticsearch.org/guide/reference/api/multi-search.html
        # request may be a hash with the templates names as keys and the variable hash as value
        # or you can also use an array of arrays.
        # The variables are an hash of variables that will be used to render the msearch template
        def multi_search(requests, variables={})
          lines    = requests.map { |name, vars| templates[name].to_msearch(vars) }.join()
          template = Template.new('GET', '/<<index>>/<<type>>/_msearch')
          template.send(:do_render, variables.merge(:data => lines)) do |http_response|
            responses   = []
            es_response = MultiJson.decode(http_response.body)
            es_response['responses'].each_with_index do |raw_result, i|
              name, vars = requests[i]
              result     = Result.new(templates[name], vars, http_response, raw_result)
              responses << (vars[:raw_result] ? result : vars[:context].flex_result(result))
            end
            es_response['responses'] = responses
            def es_response.responses
              self['responses']
            end
            es_response
          end
        end

        # implements search_type=scan (http://www.elasticsearch.org/guide/reference/api/search/search-type.html)
        def scan_search(template, vars={}, &block)
          template    = template.is_a?(Flex::Template) ? template : templates[template]
          vars        = Variables.new( :params => { :search_type => 'scan',
                                                    :scroll      => '5m',
                                                    :size        => 50 } ).deep_merge(vars)
          scroll_temp = Flex::Template.new( :get,
                                            '/_search/scroll',
                                            nil,
                                            :params => { :scroll => vars[:params][:scroll] } )
          search_res  = template.render vars
          scroll_id   = search_res['_scroll_id']
          while (result = scroll_temp.render(:data => scroll_id)) do
            break if result['hits']['hits'].empty?
            scroll_id = result['_scroll_id']
            block.call result
          end
        end

        # implements search_type=count (http://www.elasticsearch.org/guide/reference/api/search/search-type.html)
        def count_search(template, vars={})
          template = template.is_a?(Flex::Template) ? template : templates[template]
          template.render Variables.new(:params => {:search_type => 'count'}).deep_merge(vars)
        end

      end
    end
  end
end