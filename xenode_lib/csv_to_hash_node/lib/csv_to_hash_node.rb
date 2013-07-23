# Copyright Nodally Technologies Inc. 2013
# Licensed under the Open Software License version 3.0
# http://opensource.org/licenses/OSL-3.0

class CsvToHashNode
  include XenoCore::NodeBase
  
  # Allows the Xenode developer to initialize variables within
  # the EM-synchrony loop
  #
  # == Parameters:
  # none.
  #
  # == Returns:
  # none.
  #
  def startup
    # set defaults @has_header is always true
    # as message data is expected to be comma separated values with the first row
    # designating the headers
    @has_header = true
    # row delimeter defaults to newline "\n"
    @row_delim = "\n"
    # field or column delimeter defaults to a comma
    @col_delim = ','
  end
  
  # Processes incoming messages provided by the runtime.
  #
  # == Parameters: 
  # format::
  #   A XenoCore::Message object
  # msg.data is expected to be a set Comma Separated Values (CSV)
  # row delimited by @row_delim and column delimited by @col_delim
  # whos values are defaulted to newline ("\n") and comma (",") repectivley.
  # == Returns:
  # none.
  #
  def process_message(msg)
    mctx = "#{self.class}.#{__method__} [#{@xenode_id}]"
    begin
      if msg
        do_debug("#{mctx} - got message: #{msg.inspect}", true)
        @has_header = true
        if msg.context 
          @row_delim = msg.context[:row_delim] if msg.context[:row_delim]
          @col_delim = msg.context[:col_delim] if msg.context[:col_delim]
        end
        data = parse_csv(msg.data)
        if data && data.length > 0
          msg.data = data
          do_debug("#{mctx} - write_to_children called with: #{msg.inspect}", true)
          write_to_children(msg)
        end
      end
    rescue Exception => e
      catch_error("#{mctx} - #{e.inspect} #{e.backtrace}")
    end
  end
  
  def parse_csv(data)
    mctx = "#{self.class}.#{__method__} [#{@xenode_id}]"
    ret_val = []
    header = nil
    if data
      
      # do_debug is implemented in xenode_base
      do_debug("#{mctx} - data: #{data.inspect}")
      
      data.force_encoding(Encoding::UTF_8).split(@row_delim).each do |line|
        line.chomp!
        if @has_header
          header = line.split(@col_delim)
          @has_header = false
        else
          cols = line.split(@col_delim)
          tmp_hash = {}
          cols.each_index do |index|
            key = header[index].downcase.to_sym
            tmp_hash[key] = cols[index]
          end
          ret_val << tmp_hash
        end
      end
    end
    ret_val
  end
  
end
