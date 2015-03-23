module ActiveModel
  class Serializer
    class Adapter
      class JsonApi < Adapter
        def initialize(serializer, options = {})
          super
          serializer.root = true
          @hash = {}
          @top = @options.fetch(:top) { @hash }

          if fields = options.delete(:fields)
            @fieldset = ActiveModel::Serializer::Fieldset.new(fields, serializer.json_key)
          else
            @fieldset = options[:fieldset]
          end
        end

        def serializable_hash(options = {})
          if serializer.respond_to?(:each)
            @hash[:data] = serializer.map do |s|
              self.class.new(s, @options.merge(top: @top, fieldset: @fieldset)).serializable_hash[:data]
            end
          else
            @hash = cached_object do
              @hash[:data] = attributes_for_serializer(serializer, @options)
              add_resource_links(@hash[:data], serializer)
              @hash
            end
          end
          @hash
        end

        private

        def add_links(resource, name, serializers)
          resource[:links] ||= {}
          resource[:links][name] ||= { linkage: [] }
          resource[:links][name][:linkage] += serializers.map { |serializer| { type: serializer.type, id: serializer.id.to_s } }
        end

        def add_link(resource, name, serializer)
          resource[:links] ||= {}
          resource[:links][name] = { linkage: nil }

          if serializer && serializer.object
            resource[:links][name][:linkage] = { type: serializer.type, id: serializer.id.to_s }
          end
        end

        def add_included(resource_name, serializers, parent = nil)
          serializers = Array(serializers) unless serializers.respond_to?(:each)

          resource_path = [parent, resource_name].compact.join('.')

          if include_assoc?(resource_path)
            @top[:included] ||= []

            serializers.each do |serializer|
              attrs = attributes_for_serializer(serializer, @options)

              add_resource_links(attrs, serializer, add_included: false)

              @top[:included].push(attrs) unless @top[:included].include?(attrs)
            end
          end

          serializers.each do |serializer|
            serializer.each_association do |name, association, opts|
              add_included(name, association, resource_path) if association
            end if include_nested_assoc? resource_path
          end
        end


        def attributes_for_serializer(serializer, options)
          if serializer.respond_to?(:each)
            result = []
            serializer.each do |object|
              options[:fields] = @fieldset && @fieldset.fields_for(serializer)
              options[:required_fields] = [:id, :type]
              attributes = object.attributes(options)
              attributes[:id] = attributes[:id].to_s
              result << attributes
            end
          else
            options[:fields] = @fieldset && @fieldset.fields_for(serializer)
            options[:required_fields] = [:id, :type]
            result = serializer.attributes(options)
            result[:id] = result[:id].to_s
          end

          result
        end

        def include_assoc?(assoc)
          return false unless @options[:include]
          check_assoc("#{assoc}$")
        end

        def include_nested_assoc?(assoc)
          return false unless @options[:include]
          check_assoc("#{assoc}.")
        end

        def check_assoc(assoc)
          include_opt = @options[:include]
          include_opt = include_opt.split(',') if include_opt.is_a?(String)
          include_opt.any? do |s|
            s.match(/^#{assoc.gsub('.', '\.')}/)
          end
        end

        def add_resource_links(attrs, serializer, options = {})
          options[:add_included] = options.fetch(:add_included, true)

          serializer.each_association do |name, association, opts|
            attrs[:links] ||= {}

            if association.respond_to?(:each)
              add_links(attrs, name, association)
            else
              add_link(attrs, name, association)
            end

            if options[:add_included]
              Array(association).each do |association|
                add_included(name, association)
              end
            end
          end
        end
      end
    end
  end
end
