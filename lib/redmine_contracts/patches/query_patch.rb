module RedmineContracts
  module Patches
    module QueryPatch
      def self.included(base)
        base.extend(ClassMethods)

        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable

          alias_method_chain :available_filters, :deliverable
          alias_method_chain :available_filters, :contract

          alias_method_chain :sql_for_field, :contract

          alias_method_chain :issues, :deliverable
          alias_method_chain :issues, :contract

          # Override Query#count_by_group to allow adding include options like
          # Query#issues
          # TODO: core bug: Query#issue_count_by_group doesn't allow setting
          # options like Query#issue does.
          def issue_count_by_group(options={})
            includes = ([:status, :project] + (options[:include] || [])).uniq
            
            r = nil
            if grouped?
              begin
                # Rails will raise an (unexpected) RecordNotFound if there's only a nil group value
                r = Issue.count(:group => group_by_statement, :include => includes, :conditions => statement)
              rescue ActiveRecord::RecordNotFound
                r = {nil => issue_count}
              end
              c = group_by_column
              if c.is_a?(QueryCustomFieldColumn)
                r = r.keys.inject({}) {|h, k| h[c.custom_field.cast_value(k)] = r[k]; h}
              end
            end
            r
          rescue ::ActiveRecord::StatementInvalid => e
            raise ::Query::StatementInvalid.new(e.message)
          end

          alias_method_chain :issue_count_by_group, :contract
        end
      end

      module ClassMethods
      end

      module InstanceMethods
        # TODO: Should have an API on the Redmine core for this
        def available_filters_with_deliverable
          @available_filters = available_filters_without_deliverable

          if project
            deliverable_filters = {
              "deliverable_id" => {
                :type => :list_optional,
                :order => 15,
                :values => project.deliverables.by_title.collect { |d| [d.title, d.id.to_s] }
              }
            }
            return @available_filters.merge(deliverable_filters)
          else
            return @available_filters
          end

        end

        # TODO: Should have an API on the Redmine core for this
        def available_filters_with_contract
          @available_filters = available_filters_without_contract

          if project
            contract_filters = {
              "contract_id" => {
                :type => :list_optional,
                :order => 16,
                :values => project.contracts.by_name.collect { |d| [d.name, d.id.to_s] }
              }
            }
            return @available_filters.merge(contract_filters)
          else
            return @available_filters
          end

        end

        def sql_for_field_with_contract(field, operator, value, db_table, db_field, is_custom_filter=false)
          if field != "contract_id"
            return sql_for_field_without_contract(field, operator, value, db_table, db_field, is_custom_filter)
          else
            # Contracts > Deliverables > Issue
            case operator
            when "="
              contracts = value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",")
              inner_select = "(SELECT id from deliverables where deliverables.contract_id IN (#{contracts}))"
              sql = "#{Issue.table_name}.deliverable_id IN (#{inner_select})"
            when "!"
              contracts = value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",")
              inner_select = "(SELECT id from deliverables where deliverables.contract_id IN (#{contracts}))"
              sql = "(#{Issue.table_name}.deliverable_id IS NULL OR #{Issue.table_name}.deliverable_id NOT IN (#{inner_select}))"
            when "!*"
              # If it doesn't have a deliverable, it can't have a contract
              sql = "#{Issue.table_name}.deliverable_id IS NULL"
            when "*"
              # If it has a deliverable, it must have a contract
              sql = "#{Issue.table_name}.deliverable_id IS NOT NULL"
            end

            return sql
          end
        end

        # Add the deliverables into the includes
        #
        # Used with grouping
        def issues_with_deliverable(options={})
          options[:include] ||= []
          options[:include] << :deliverable

          issues_without_deliverable(options)
        end

        # Add the contracts into the includes
        #
        # Used with grouping
        def issues_with_contract(options={})
          options[:include] ||= []
          options[:include] << {:deliverable => :contract}

          issues_without_contract(options)
        end

        # Add the contracts into the includes
        #
        # Used with grouping
        def issue_count_by_group_with_contract(options={})
          options[:include] ||= []
          options[:include] << {:deliverable => :contract}

          issue_count_by_group_without_contract(options)
        end


      end
    end
  end
end
