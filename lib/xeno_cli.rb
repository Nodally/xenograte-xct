# Copyright Nodally Technologies Inc. 2013
# Licensed under the Open Software License version 3.0
# http://opensource.org/licenses/OSL-3.0

require 'pathname'
require 'yaml'
require 'redis'
require 'fileutils'

module Xeno
  
  class RunXenode < ::Escort::ActionCommand::Base


    def execute

      lib_dir = Xeno::lib_dir
      
      # puts "execute options: #{options} arguments: #{arguments}"
      
      # puts "lib_dir: #{lib_dir.inspect}"
      
      if command_name.to_s.downcase == 'xenode'

        if command_options[:xenode_id_given] && command_options[:xenode_file_given] && command_options[:xenode_klass_given]
          klass = command_options[:xenode_klass]
          xenode_id = command_options[:xenode_id]
          xenode_file = command_options[:xenode_file]
          
          xenode ||= {}
          xenode['klass'] = klass
          xenode['id']    = xenode_id
          xenode['path']  = xenode_file
          
          # Xeno::write_configs(xenode)
          
          puts "Starting Xenode: #{xenode_id}"
          
          xenode_pid = Xeno::get_xenode_pid(xenode_id)
          
          # don't start it if it is already running
          unless xenode_pid 
            # run the xenode
            exec_cmd = "ruby -I #{lib_dir} -- #{lib_dir}/instance_xenode.rb "
            exec_cmd << "-f #{xenode_file} -k #{klass} "
            exec_cmd << "-i #{xenode_id.to_s} "
            exec_cmd << "-d " if @debug

            # pid = fork do
            #   exec(exec_cmd)
            # end
            # 
            # Process.detach(pid)
            system("#{exec_cmd} &")
            
          end

        end

      end

    end

  end

  class StopXenode < ::Escort::ActionCommand::Base

    def execute

      lib_dir = Xeno::lib_dir

      if command_name.to_s.downcase == 'xenode'

        if command_options[:xenode_id_given]
          xenode_id = command_options[:xenode_id]
          # see if pid file exists
          pid_path = File.expand_path(File.join(lib_dir,'..','run','pids',"#{xenode_id}_pid"))
          if pid_path && File.exist?(pid_path)
            # yes the file could disappear before below is called so check again.
            pid = File.read(pid_path) if File.exist?(pid_path)
            if pid
              unless pid.to_s.empty?
                begin
                  Process.kill("TERM", pid.to_i)
                  puts "Xenode #{xenode_id} stopped."
                rescue Errno::ESRCH
                end
              end
            else
              puts "Pid file found at: #{pid_path}. But file was empty. (no pid value)"
            end
          else
            puts "Xenode #{xenode_id} already stopped. No pid file found at: #{pid_path}"
          end
        end

      end

    end

  end

  class RunXenoFlow < ::Escort::ActionCommand::Base

    def execute
    
      begin
        if command_name.to_s.downcase == 'xenoflow'
          if command_options[:xenoflow_file_given] 

            xenoflow_id   = command_options[:xenoflow_id]
            xenoflow_file = command_options[:xenoflow_file]
            xenoflow = Xeno::load_xenoflow(xenoflow_file)
            # puts "* xenoflow: #{xenoflow.inspect}"
            
            if xenoflow_id
              run_xenoflow(xenoflow[xenoflow_id])
            else
              xenoflow.each_value do |xflow|
                run_xenoflow(xflow)
              end
            end
          else
            puts "Error: You must supply a xenoflow file name."
          end
          #END if
        end
        #END if
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end
    
    def run_xenoflow(xenoflow)
      
      lib_dir = Xeno::lib_dir
      
      if xenoflow
        puts "* CLI attempt to run xenoflow: #{xenoflow['id']}"
        if xenoflow['xenodes']
          xenoflow['xenodes'].each_value do |xenode|
            
            # get options
            xenode_id   = xenode['id']
            xenode_file = xenode['path']
            xenode_class = xenode['klass']

            # get klass nmae if not provided
            unless xenode['klass']
              xenode_class = Xeno::get_xenode_class(xenode_file)
              xenode['klass'] = xenode_class
            end
            
            # get xeno_conf
            # may move this to a helper later because we may need this in other commands
            xeno_conf = {
              :redis_host => '127.0.0.1',
              :redis_port => 6379,
              :redis_db => 0
            }
            xeno_conf_file = File.join(lib_dir, '..', 'bin', 'xeno.yml')
            if File.exist?(xeno_conf_file)
              hash = YAML.load(File.read(xeno_conf_file))
              if hash
                symbolized_hash = Xeno::symbolize_hash_keys(hash)
                xeno_conf.merge!(symbolized_hash)
                # puts "* CLI checking xeno_conf: #{xeno_conf.inspect}"
              end
            end
            #END if
            
            if xenode_class
              
              Xeno::write_configs(xenode)
              
              xenode_pid = Xeno::get_xenode_pid(xenode_id)
              # don't start it if it is already running
              unless xenode_pid
                puts "* CLI attempt to run xenode: #{xenode_id} (#{xenode_class})\n"
              
                # run the xenode
                exec_cmd = "ruby -I #{lib_dir} -- #{lib_dir}/instance_xenode.rb "
                exec_cmd << "-f #{xenode_file} -k #{xenode_class} "
                exec_cmd << "-i #{xenode_id.to_s} "
                exec_cmd << "-d " if @debug
                exec_cmd << "--redis-host #{xeno_conf[:redis_host]} " if xeno_conf[:redis_host]
                exec_cmd << "--redis-port #{xeno_conf[:redis_port]} " if xeno_conf[:redis_port]
                exec_cmd << "--redis-db #{xeno_conf[:redis_db]} " if xeno_conf[:redis_db]


                # pid = fork do
                #   exec(exec_cmd)
                # end
                # Process.detach(pid)
              
                system("#{exec_cmd} &")
            
              else
                puts "* CLI found xenode #{xenode_id} (#{xenode_class}) is already running in pid: #{xenode_pid}\n"  
              end
            else
              puts "* CLI cannot find the class in xenode file: #{xenode_file}\n\n"
            end
            #END if
          end
          #END each_value
        else
          puts "xenodes are empty for xenoflow #{xenoflow_id}"
        end
        #END if
      end
      #END if
    end
    #END run_xenoflow
  end

  class StopXenoFlow < ::Escort::ActionCommand::Base

    def execute
      lib_dir = Xeno::lib_dir
      
      begin
        if command_name.to_s.downcase == 'xenoflow'
          if command_options[:xenoflow_file_given] 

            xenoflow_id   = command_options[:xenoflow_id]
            xenoflow_file = command_options[:xenoflow_file]
            xenoflow = Xeno::load_xenoflow(xenoflow_file)
            # puts "* xenoflow: #{xenoflow.inspect}"
            
            if xenoflow_id
              stop_xenoflow(xenoflow[xenoflow_id])
            else
              xenoflow.each_value do |xflow|
                stop_xenoflow(xflow)
              end
            end
          else
            puts "Error: You must supply a xenoflow file name."
          end
          #END if
        end
        #END if
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
      
    end
    
    def stop_xenoflow(xenoflow)
      lib_dir = Xeno::lib_dir
      
      if xenoflow
        puts "* CLI attempt to stop xenoflow: #{xenoflow['id']}"
        if xenoflow['xenodes']
          
          xenoflow['xenodes'].each_value do |xenode|
          
            # get options
            xenode_id   = xenode['id']
            xenode_file = xenode['path']
            xenode_class = xenode['klass']
          
            # get klass nmae if not provided
            unless xenode['klass']
              xenode_class = Xeno::get_xenode_class(xenode_file)
              xenode['klass'] = xenode_class
            end
          
            unless xenode_class
              puts "* CLI cannot find the class for xenode #{xenode_id}, but will process to stop #{xenode_id} anyways"
            end
          
            xenode_pid = Xeno::get_xenode_pid(xenode_id)
            # don't start it if it is already running
            if xenode_pid
              puts "* CLI attempt to stop xenode: #{xenode_id} (#{xenode_class})\n"
          
              begin
                Process.kill("TERM", xenode_pid.to_i)
                puts "* CLI has stopped xenode #{xenode_id} (#{xenode_class}) in pid: #{xenode_pid}"
              rescue Errno::ESRCH
              end
            else
              puts "* CLI found xenode #{xenode_id} (#{xenode_class}) is already stopped."
            end
            #END if
          end
          #END each_value
        end
        #END if
      end
      #END if
    end
    #END stop_xenoflow
    
  end
  
  class ClearXenoFlow < ::Escort::ActionCommand::Base

    def execute
      lib_dir = Xeno::lib_dir

      begin
        if command_name.to_s.downcase == 'xenoflow'
          if command_options[:xenoflow_file_given] && command_options[:xenoflow_id_given]
            
            # get the passed in vars from the CLI
            xenoflow_id   = command_options[:xenoflow_id]
            xenoflow_file = command_options[:xenoflow_file]
            
            # load the xenoflow from the yaml file
            xenoflow = Xeno::load_xenoflow(xenoflow_id, xenoflow_file)

            if xenoflow && xenoflow[xenoflow_id]
              if xenoflow[xenoflow_id]['xenodes']
                
                # loop through each xenode in the xenoflow
                xenoflow[xenoflow_id]['xenodes'].each_value do |xenode|
                  
                  # get the xenode_id
                  xenode_id   = xenode['id']
                  
                  # clear the log
                  log_path = File.expand_path(File.join(lib_dir,'..','log',"#{xenode_id}.log"))
                  puts "clearing log: #{log_path}"
                  File.unlink(log_path) if File.exist?(log_path)
                  puts "Log messages for xenode: #{xenode_id} cleared."
                  
                  # clear the runtime configs
                  run_cfg_path = File.expand_path(File.join(Xeno::lib_dir, '..', 'run', 'xenodes', xenode_id))
                  puts "clearing runtime files in: #{run_cfg_path}"
                  FileUtils.remove_dir(run_cfg_path, true) if File.exist?(run_cfg_path)
                  puts "Runtime files cleared for xenode: #{xenode_id}."

                end
              else
                puts "xenodes are empty for xenoflow #{xenoflow_id}"
              end
            end

          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end

  end
  
  class ClearMessages < ::Escort::ActionCommand::Base
    def execute
      begin
        if command_name.to_s.downcase == 'message'
          if command_options[:xenode_id_given]
            redis_port = nil
            rdb = redis_port ? Redis.new(:port => redis_port) : Redis.new
            xenode_id  = command_options[:xenode_id]
            msg_key = "#{xenode_id}:msg"
            rdb.del(msg_key)
            puts "messages for xenode: #{xenode_id} cleared."
          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end
  end

  class ListMessages < ::Escort::ActionCommand::Base
    def execute
      lib_dir = Xeno::lib_dir

      require File.join(lib_dir,"xeno_message")

      begin
        if command_name.to_s.downcase == 'message'
          if command_options[:xenode_id_given]
            redis_port = nil
            rdb = redis_port ? Redis.new(:port => redis_port) : Redis.new
            xenode_id  = command_options[:xenode_id]
            msg_key = "#{xenode_id}:msg"
            msgs = rdb.lrange(msg_key, 0, -1)
            if msgs
              puts
              puts "Messages for Xenode: #{xenode_id}"
              puts "-------------------------------------------"
              msgs.each do |m|
                m = XenoCore::Message.new.load(m)
                puts m.to_hash
              end
              puts
            end
          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end
  end
  
  class WriteConfig < ::Escort::ActionCommand::Base

    def execute
      lib_dir = Xeno::lib_dir

      begin
        if command_name.to_s.downcase == 'config'
          if command_options[:xenoflow_file_given] && command_options[:xenoflow_id_given]

            xenoflow_id   = command_options[:xenoflow_id]
            xenoflow_file = command_options[:xenoflow_file]
            xenoflow = Xeno::load_xenoflow(xenoflow_id, xenoflow_file)

            if xenoflow && xenoflow[xenoflow_id]
              if xenoflow[xenoflow_id]['xenodes']
                xenoflow[xenoflow_id]['xenodes'].each_value do |xenode|
                  xenode_id   = xenode['id']
                  Xeno::write_configs(xenode)
                  puts "Writing config for Xenode: #{xenode_id}"
                end
              else
                puts "xenodes are empty for xenoflow #{xenoflow_id}"
              end
            end

          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end

  end
  
  class WriteMessage < ::Escort::ActionCommand::Base

    def execute
      lib_dir = Xeno::lib_dir

      require File.join(lib_dir,"xeno_message")

      begin
        if command_name.to_s.downcase == 'message'

          if command_options[:xenode_id_given]

            data = context = redis_port = nil

            xenode_id  = command_options[:xenode_id]

            xmsg         = XenoCore::Message.new
            xmsg.from_id = "console"
            xmsg.to_id   = xenode_id

            if command_options[:msg_file_given]
              fp = command_options[:msg_file]
              basename = File.basename(fp)
              if basename.downcase.include?(".csv")
                if command_options[:context_given]
                  context = command_options[:context]
                  xmsg.context = Xeno::text_to_hash(context) if context
                end
                msg = File.read(fp)
                xmsg.data = msg
              elsif basename.downcase.include?(".yml")
                msg = YAML.load(File.read(fp)) if File.exist?(fp)
                xmsg.load(msg) if msg.is_a?(Hash)
              end
            else
              data       = command_options[:data]       if command_options[:data_given]
              context    = command_options[:context]    if command_options[:context_given]
              puts "context: #{context.inspect}" if context
              data_hash = Xeno::text_to_hash(data)
              xmsg.data = data_hash ? data_hash : data

              context_hash = Xeno::text_to_hash(context)
              xmsg.context = context_hash ? context_hash : context
            end

            redis_port = command_options[:redis_port] if command_options[:redis_port]

            rdb = redis_port ? Redis.new(:port => redis_port) : Redis.new

            msg_key = "#{xenode_id}:msg"
            pub_key = "#{xenode_id}:msgpub"

            rdb.lpush(msg_key, xmsg.pack)
            rdb.publish(pub_key, msg_key)

            puts "Message written to #{xenode_id}"

          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end

    end

  end

  class ClearLogMessages < ::Escort::ActionCommand::Base
    def execute
      begin

        lib_dir = Xeno::lib_dir
        
        if command_name.to_s.downcase == 'log'
          if command_options[:xenode_id_given]
            xenode_id = command_options[:xenode_id]
            log_path = File.expand_path(File.join(lib_dir,'..','log',"#{xenode_id}.log"))
            puts "clearing log: #{log_path}"
            File.unlink(log_path) if File.exist?(log_path)
            puts "Log messages for xenode: #{xenode_id} cleared."
          else
            puts "*WARNING* This will clear all logs. Do you want to proceed? [y/n]:"
            user_input = STDIN.gets.chomp
            if user_input[0] == "Y" || user_input[0] == "y"
              log_path = File.expand_path(File.join(lib_dir,'..','log',"*.log"))
              puts "clearing log: #{log_path}"
              FileUtils.rm Dir.glob(log_path)
              puts "All log messages cleared."
            else
              puts "Cancelled clearing all log messages."
            end
          end
        end
      rescue Exception => e
        puts "#{e.inspect} #{e.backtrace}"
      end
    end
  end
  
  def self.get_xenode_pid(xenode_id)
    ret_val = nil
    pid_path = File.expand_path(File.join(lib_dir,'..','run','pids',"#{xenode_id}_pid"))
    # puts "* CLI checking the pid_path: #{pid_path}"
    if File.exist?(pid_path)
      pid = nil
      pid = File.read(pid_path) if File.exist?(pid_path)
      # puts "* CLI found pid for #{xenode_id}: #{pid.inspect}"
      if pid
        begin
          Process.kill(0, pid.to_i)
          # puts "* CLI found #{xenode_id} is running with pid: #{pid}"
          ret_val = pid
        rescue Errno::ESRCH
        end
      end
    end
    ret_val
  end
  
  def self.load_xenoflow(xenoflow_file)
    ret_val = {}
    lib_dir = Xeno::lib_dir
    path = nil

    xenoflows_dir = File.expand_path(File.join(lib_dir,'..','xenoflows'))
    ext = File.extname(xenoflow_file)
    xenoflow_file = "#{xenoflow_file}.yml" unless ext && ext.downcase == '.yml'
    path = File.join(xenoflows_dir, xenoflow_file)

    if path && File.exist?(path)
      yml = File.read(path)
      xenoflow = YAML.load(yml) if yml
      xenoflow.each_pair do |k,v|
        v['id'] = k
        v['xenodes'].each_pair do |xk, xv|
          xv['id'] = xk
        end
      end
      ret_val = xenoflow if xenoflow
    end
    
    ret_val
  end

  def self.write_configs(xenode)
    if xenode

      xenode_id   = xenode['id']
      xenode_file = xenode['path']
      children = xenode['children']

      # default config
      default_cfg_path = File.expand_path(File.join(Xeno::lib_dir, '..', 'xenode_lib', xenode_file, 'config', 'config.yml'))
      # run config
      run_cfg_path = File.expand_path(File.join(Xeno::lib_dir, '..', 'run', 'xenodes', xenode_id, 'config', 'config.yml'))

      def_cfg = run_cfg = nil
      
      comments = ""
      comments << "# #{xenode_file}\n"
      
      if File.exist?(default_cfg_path)
        yml = File.read(default_cfg_path)
        def_cfg = YAML.load(yml) if yml
      end

      if File.exist?(run_cfg_path)
        # puts "Config file exists #{run_cfg_path}"

        yml = File.read(run_cfg_path)
        run_cfg = YAML.load(yml) if yml
        run_cfg ||= {}
        run_cfg['children'] = children
        
        data_out = YAML.dump(run_cfg)
        
        File.open(run_cfg_path, "w") do |f|
          f.write(comments)
          f.write(data_out)
        end

      else

        puts "* CLI creates config file for #{xenode_id} in run directory"

        def_cfg ||= {}

        def_cfg['loop_delay'] = 5.0 unless def_cfg['loop_delay']
        def_cfg['enabled'] = true unless def_cfg['enabled']
        def_cfg['debug'] = false unless def_cfg['debug']
        def_cfg['children'] = children

        # make sure the path exists
        FileUtils.mkdir_p(File.dirname(run_cfg_path))
        
        data_out = YAML.dump(def_cfg)
        
        File.open(run_cfg_path, "w") do |f|
          f.write(comments)
          f.write(data_out)
        end

      end

    end
  end
  
  def self.get_xenode_class(xenode_file)
    ret_val = nil
    
    fp = File.expand_path(File.join(Xeno::lib_dir, '..', 'xenode_lib', xenode_file))
    if Dir.exist?(fp)
      files = Dir.glob(File.join(fp, 'lib', '*.rb'))
      if files.length == 1
        File.read(files[0]).each_line do |line|
          # check if meta is in flie to find class
          line.chomp!.strip!
          if line[0..10] == '#xeno-meta:'
            ret_val = line.split(':')[1]
            puts "ret_val: #{ret_val.inspect}"
            break
          elsif line[0..4] == 'class'
            ret_val = line.split('class')[1].strip
            break
          end
        end
      end
    end
    
    ret_val
  end
  
  
  def self.lib_dir
    Pathname.new(__FILE__).realpath.dirname
  end
  
  #-------------------------------------------------------------------------------------
  #  helpers
  #-------------------------------------------------------------------------------------
  
  def self.text_to_hash(hash_text)
    ret_val = nil
    if hash_text
      ret_val = hash_text
      if hash_text && hash_text.include?(':')
        ret_val = {}
        if hash_text.include?(',')
          hash_text.split(',').each do |pair|
            key, val = pair.split(':')
            ret_val[key.to_sym] = val
          end
        else
          key, val = hash_text.split(':')
          ret_val[key.to_sym] = val
        end
      end
    end
    ret_val
  end
  
  def self.symbolize_hash_keys(hash)
    ret_val = {}
    hash.each_pair do |k,v|
      v = Xeno::symbolize_hash_keys(v) if v.is_a?(Hash)
      ret_val[k.to_sym] = v
    end
    ret_val
  end
  # END symbolize_hash_keys
  
  
  
end
