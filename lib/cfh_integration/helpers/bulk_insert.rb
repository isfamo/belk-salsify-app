########################################################################
################# https://github.com/jamis/bulk_insert #################
#################       Copyright 2015 Jamis Buck      #################

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# We needed to support postgresql 9.5 `ON CONFLICT` feature
# so I decided not to use the gem's pristine version

module BulkInsert
  class Worker
    attr_reader :connection
    attr_accessor :set_size
    attr_accessor :after_save_callback

    def initialize(connection, table_name, column_names, set_size=500)
      @connection = connection
      @set_size = set_size

      columns = connection.columns(table_name)
      column_map = columns.inject({}) { |h, c| h.update(c.name => c) }

      @columns = column_names.map { |name| column_map[name.to_s] }
      @table_name = connection.quote_table_name(table_name)
      @column_names = column_names.map { |name| connection.quote_column_name(name) }.join(",")

      @after_save_callback = nil

      @set = []
    end

    def pending?
      @set.any?
    end

    def pending_count
      @set.count
    end

    def add(values)
      save! if @set.length >= set_size

      values = values.with_indifferent_access if values.is_a?(Hash)
      mapped = @columns.map.with_index do |column, index|
          value_exists = values.is_a?(Hash) ? values.key?(column.name) : (index < values.length)
          if !value_exists
            if column.default.present?
              column.default
            elsif column.name == "created_at" || column.name == "updated_at"
              :__timestamp_placeholder
            else
              nil
            end
          else
            values.is_a?(Hash) ? values[column.name] : values[index]
          end
        end

      @set.push(mapped)
      self
    end

    def add_all(rows)
      rows.each { |row| add(row) }
      self
    end

    def after_save(&block)
      @after_save_callback = block
    end

    def save!
      if pending?
        sql = "INSERT INTO #{@table_name} (#{@column_names}) VALUES "
        @now = Time.now

        rows = []
        @set.each do |row|
          values = []
          @columns.zip(row) do |column, value|
            value = @now if value == :__timestamp_placeholder

            if ActiveRecord::VERSION::STRING >= "5.0.0"
              value = @connection.type_cast_from_column(column, value) if column
              values << @connection.quote(value)
            else
              values << @connection.quote(value, column)
            end
          end
          rows << "(#{values.join(',')})"
        end

        sql << rows.join(',')
        #### Extended the gem code with the Conflict Resolution ####
        sql << ' ON CONFLICT DO NOTHING'
        @connection.execute(sql)

        @after_save_callback.() if @after_save_callback

        @set.clear
      end

      self
    end
  end
end