module Pocus
  class Response < OpenStruct; end

  class Resource
    attr_reader :path
    attr_accessor :parent

    def self.tag
      name.split('::').last.downcase
    end

    def self.tag_multiple
      tag.concat('s')
    end

    def initialize(attributes)
      assign_attributes(attributes)
    end

    def assign_attributes(attributes)
      attributes.each do |ck, v|
        k = underscore(ck)
        self.class.__send__(:attr_accessor, k) unless respond_to?(k)
        send("#{k}=", v)
      end
    end

    def fields
      field_names.reduce(Hash[]) do |hash, field_name|
        hash.tap { |h| h[camelize field_name] = send field_name }
      end
    end

    # Fetch and instantiate a single resource from a path.
    def get(request_path, klass)
      response = session.send_request('GET', path+request_path)
      data = response.fetch(klass.tag)
      response[klass.tag] = klass.new(data.merge(parent: self))
      Response.new response
    end

    def get_multiple(request_path, klass, filters = {})
      response = session.send_request('GET', path+request_path, camelize_filters(filters))
      data = response.fetch(klass.tag_multiple)
      response[klass.tag_multiple] = data.map { |fields| klass.new(fields.merge(parent: self)) }
      Response.new response
    end

    def logger
      session.logger
    end

    def post
      response = session.send_request('POST', path, fields)
      assign_attributes(response.fetch(self.class.tag))
      response[self.class.tag] = self
      Response.new(response)
    end

    def post_multiple(request_path, resources)
      request_tag = resources.first.class.tag_multiple
      response = session.send_request('POST', path+request_path, resources.map(&:fields))
      data = response.fetch(request_tag)
      data.each_with_index { |fields, idx| resources[idx].assign_attributes(fields) }
      response[request_tag] = resources
      Response.new(response)
    end

    # Fetch and update this resource from a path.
    def reload
      response = session.send_request('GET', path)
      assign_attributes(response.fetch(self.class.tag))
      assign_attributes(errors: response['errors'], warnings: response['warnings'])
      self
    end

    def session
      parent.session
    end

    protected

    def required(attributes, attr_names)
      missing = attr_names - attributes.keys
      fail "missing required atrributes: #{missing.inspect}" if missing.any?
    end

    def camelize(str)
      return str.to_s unless str.to_s.include?(?_)
      parts = str.to_s.split('_')
      first = parts.shift
      first + parts.each {|s| s.capitalize! }.join
    end

    def camelize_filters(hash)
      hash.reduce({}) do |h, e|
        key = camelize(e[0])
        h[key] = e[1]
        h[key+'SearchType'] = 'eq'
        h
      end
    end

    def field_names
      instance_variables.map { |n| n.to_s.sub('@','').to_sym } - [:session, :parent, :path]
    end

    def underscore(camel_cased_word)
      camel_cased_word.to_s.dup.tap do |word|
        word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
        word.downcase!
      end
    end
  end
end
