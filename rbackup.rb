#
# Author : Olivier Delbos , 18/06/2010
# Status : Functional draft prototype, waiting API and DSL specs validations
#
# Purpose : DSL around the rsync command.
#           Supply a powerfull way to manage complex rsync commands generation.
#           Also provide a way to execute, test, dry-run, parse result ...
#

module RBack

  # About default configuration.
  @@_default = {
    :execute      => true,    # Execute rsync process. Otherwise, simply compute rsync cmd.
    :dry_run      => true,
    :rsync_args   => '-rltDz --update --stats',
    :stats        => true,    # TODO Unmanaged
    :progress     => false,   # Unmanaged
    :report       => false,
    :delete       => false,   # Unmanaged
    :safe_links   => false,   # Unmanaged
    :use_ssh      => true,    # Unmanaged
    :ssh_key      => '~/.ssh/rsa_id.pub',
    :log          => false    # Unmanaged
  }
  def self.default(*args)
    return @@_default if args.size == 0
    @@_default.merge!(args[0])
  end
  def self.set(n, v);    @@_default[n] = v;               end


  # About RBack module configuration.
  @@_conf = nil
	def self.reset_conf;   @@_conf = nil;                   end
	def self.get_conf;     @@_conf ||= RBack::Conf.new;     end




	#
	# Configuration.
	#
	class Conf
		attr_accessor :hosts, :sources, :exclude_groups, :syncs
		def initialize()
			@hosts, @sources, @exclude_groups, @syncs  = { }, { }, { }, { }
		end
		def self.reset;      RBack::reset_conf;      end
		def self.get;        RBack::get_conf;        end

		def add_exclude_group(eg);   @exclude_groups[eg.sym] = eg;    end
		def has_exclude_group(sym);  @exclude_groups[sym] != nil;     end
		def get_exclude_group(sym);  @exclude_groups[sym];            end
		def add_host(h);             @hosts[h.sym] = h;	              end
		def has_host(sym);           @hosts[sym] != nil;              end
		def get_host(sym);           @hosts[sym];                     end
		def add_source(s);           @sources[s.sym] = s;	            end
		def has_source(sym);         @sources[sym] != nil;            end
		def get_source(sym);         @sources[sym];                   end
		def add_sync(s);             @syncs[s.sym] = s;               end
		def has_sync(sym);           @syncs[sym] != nil;              end
		def get_sync(sym);           @syncs[sym];                     end

		#
		# Used to encapsulate configuration.
		#
		class ExcludeGroup
			attr_accessor :sym, :patterns
			def initialize(sym)
				@sym = sym
				@patterns = []
			end
			def add(pattern)
				k = pattern.class
				@patterns << pattern if k == String
				@patterns.concat(pattern) if k == Array
				raise ArgumentError, 'Bad argument type !' if k != String and k != Array
			end
		end

		class Host
			attr_accessor :sym, :host, :user, :pwd, :ssh_key
			def initialize(sym)
				@sym = sym
			end

			# Instance methods
			def get_host;          @host;             end
			def get_user;          @user;             end
			def get_pwd;           @pwd;              end
			def ssh_key;           @ssh_key;          end

			# DSL
			def host(h);           @host = h;         end
			def user(u);           @user = u;         end
			def pwd(p);            @pwd = p;          end
			def ssh_key(s);        @ssh_key = s;      end
		end

		class Source
			attr_accessor :sym, :host, :files, :excludes
			def initialize(sym)
				@sym, @files, @excludes, @host = sym, [ ], [ ], :local
			end
      def host(h)
				raise RuntimeError, 'Error, host does not exist !' if not RBack::Conf::get.has_host(h)
        @host = h
      end
      def reset_files
        @files = []
      end
			def file(file)
				@files << file
			end
			def exclude_group(*args, &block)
				args.each do |sym|
					raise RuntimeError, 'Exclude group, not a symbol !' if sym.class != Symbol
					if not RBack::Conf.get.has_exclude_group(sym)
						raise RuntimeError, 'Exclude group not exist !'
					end
					grp = RBack::Conf.get.get_exclude_group(sym)
					@excludes = @excludes | grp.patterns
					instance_eval(&block) if block_given?
				end
			end
			def exclude(pattern)
				k = pattern.class
				if k == String
					@excludes << pattern unless @excludes.index(pattern)
				elsif k == Array
					@excludes = @excludes | pattern
				else
					raise ArgumentError, 'Bad argument type !'
				end
			end
			def remove(*args)
				args.each do |str|
					raise RuntimeError, 'Exclude group, not a string !' if str.class != String
					@excludes.delete(str)
				end
			end
		end     # / class Source

		class Sync
			attr_accessor :sym, :rsync_args, :src, :host, :to, :opts, :result
			def initialize(sym)
				@sym, @rsync_args, @src, @host, @to, @options = sym, nil, nil, nil, nil, { }
			end

      def get_rsync_args;  @rsync_args;      end
			def get_source;      @src;             end
			def get_host;        @host;            end
			def get_to;          @to;              end

      def get_safe_source
        @src ||= RBack::Conf::Source.new(:anonymous)
      end


      def error?
        report = @result[:report]
        return false unless report.class == Hash
        e, m = report[:errors], report[:messages]
        (e.class == Array and e.size > 0) or (m.class == Array and m.size > 0)
      end
      def ok?;   not error?;   end


			# For DSL configuration.
      def rsync_args(ra)
        @rsync_args = ra
      end
			def source(sym)        # Problem override access to Sync.source
				conf = RBack::Conf::get
				raise RuntimeError, 'Error, source does not exist !' if not conf.has_source(sym)
				@src = conf.get_source(sym).clone
  			@src.instance_eval(&block) if block_given?
			end
			def host(h)
				conf = RBack::Conf::get
				raise RuntimeError, 'Error, host does not exist !' if not conf.has_host(h)
				@host = conf.get_host(h).clone
			end
			def to(to)
				@to = to
			end
      def options(*args)
        @opts = args[0]
      end
			# / For DSL

			# Proxy forward methods to 'Source' object.
			# Probably better to use method missing ...
			# and forward all agrs, block, to 'source' with something
			# of an array of method valid method to proxy.
			# [:exclude_group, :exlude, :file]
			# Have to see more in detail here ...
			def exclude_group(*args, &block)
        get_safe_source.send(:exclude_group, *args, &block)
		  end
			def exclude(pattern)
        get_safe_source.send(:exclude, pattern)
		  end
			def file(f)
        get_safe_source.send(:file, f)
		  end
      # / Proxy


    	def compile
        cmd = ['rsync']

    		args = @rsync_args || RBack::default[:rsync_args]
        # TODO Manage arguments and options
        dry_run = RBack::default[:dry_run]
        dry_run = @opts[:dry_run] if $opt != nil and @opts.key? :dry_run
        args = '--dry-run ' + args if dry_run and not cmd.include? '--dry-run'
    		@src.excludes.each do |e|
    			args << " --exclude '" + e + "'"
    		end
        cmd << args

    		@src.files.each do |file|
    			cmd << file
    		end

    		use_ssh = false   # FIXME - !! Temporary Dev Horrible Hack !!
    		if use_ssh
  			  cmd << "-e 'ssh'" if use_ssh
          # TODO Detect if source is local or remote.
    		  # cmd << ' ' + host.get_user + '@' + host.get_host + ':' + to
          raise 'Sorry, not implemented !'       # TODO Not implement : 'use_ssh'
        else
          cmd << @to
        end

    		return cmd
    	end
		end     # / class Sync
	end       # / class Conf



	#
	# DSL pour simplifier la definition de la configuration.
	#
	module DSL
    # ----------------------------------------------------- Bad Code
    # Already saw proxying pattern to solve those code repetition
		def exclude_group(sym, &block)
			conf = RBack::Conf::get
			raise RuntimeError, 'Exclude group already defined !' if conf.has_exclude_group(sym)
			raise	RuntimeError, '' if not block_given?
			_c = RBack::Conf::ExcludeGroup.new(sym)
			_c.instance_eval(&block)
			conf.add_exclude_group(_c)
		end
		def host(sym, &block)
			conf = RBack::Conf::get
			raise RuntimeError, 'Exclude host already defined !' if conf.has_host(sym)
			raise	RuntimeError, '' if not block_given?
			_c = RBack::Conf::Host.new(sym)
			_c.instance_eval(&block)
			conf.add_host(_c)
		end
		def source(*args, &block)
      sym = args[0]
			conf = RBack::Conf::get
			raise RuntimeError, 'Exclude source already defined !' if conf.has_source(sym)
			raise	RuntimeError, '' if not block_given?
      _c = nil
      if (args.size == 2)
        opts = args[1]
        if opts.include?(:inherit)
      	  raise 'Inherited source does not exist !' if not conf.has_source(opts[:inherit])
    		  _c = conf.get_source(opts[:inherit]).clone
          _c.sym = sym
        end
      end
	    _c = RBack::Conf::Source.new(sym) if _c == nil
			_c.instance_eval(&block)
			conf.add_source(_c)
		end
		def sync(sym, &block)
			conf = RBack::Conf::get
			raise RuntimeError, 'Sync already defined !' if conf.has_sync(sym)
			raise	RuntimeError, '' if not block_given?
			_c = RBack::Conf::Sync.new(sym)
			_c.instance_eval(&block)
			conf.add_sync(_c)
		end
    # --------------------------------------------------- / Bad Code
	end    # / module DSL



  # --------------------------------------------------------------------------- Bad
  # TODO How to add DSL capability here without duplication of code
  # from RBack:DSL ????
  # FIXME Temporary code waiting clean refactoring.

	def self.exclude_group(sym, &block)
		raise	RuntimeError, 'Missing block !' if not block_given?
		conf = RBack::Conf::get
		raise RuntimeError, 'Exclude group already defined !' if conf.has_exclude_group(sym)
		_c = RBack::Conf::ExcludeGroup.new(sym)
		_c.instance_eval(&block)
		conf.add_exclude_group(_c)
	end
	def self.sync(sym, &block)
		raise	RuntimeError, 'Missing block !' if not block_given?
		conf = RBack::Conf::get
		raise RuntimeError, 'Sync already defined !' if conf.has_sync(sym)
		_c = RBack::Conf::Sync.new(sym)
		_c.instance_eval(&block)
		conf.add_sync(_c)
	end
  # ------------------------------------------------------------------------ / Bad


  # DSL Hack
	def self.namespace(name=nil, &block)
    raise 'No block given !' if not block_given?
    # TODO Manage 'name' argument, implement namespace capability
    instance_eval(&block)
  end


  # Run the rsync command and produce a report according to options.
	def self.run(sym=nil, &block)
    sync = nil
    if sym
      _c = RBack::Conf::get
      # TODO Move check/raise in get_sync()
      raise 'Sync configuration does not exist !' if not _c.has_sync(sym)
      sync = _c.get_sync(sym).clone
    else
      sync = RBack::Conf::Sync.new(sym)
    end
    sync.instance_eval(&block) if block_given?

    cmd = sync.compile()


    opts = sync.opts
    has_report = RBack::default[:report]
    has_report = opts[:report] if opts != nil and opts.include?(:report)

    result = {} if has_report
    result[:cmd] = cmd if has_report

    # Execute rsync command ?

    execute = RBack::default[:execute]
    execute = opts[:execute] if opts != nil and opts.include?(:execute)
    # execute = sync.opts.include?(:execute) ? sync.opts[:execute] : RBack::default[:execute]

    if execute
      r = IO.popen(cmd.join(' ') + ' 2>&1').readlines.join
      result[:output] = r
      result[:report] = parse_result(r) if has_report
    else
      # Nothing ...
    end
    sync.result = result if has_report
    return sync
	end


  # Very simple parsing of rsync commend raw result.
  def self.parse_result(raw_result)
    sp = raw_result.split("\n")
    sp.shift if sp.class == Array
    files, stats, errors, messages, is_file = [ ], [ ], [ ], [ ], true
    sp.each do |line|
      next if line == nil or line == ''
      next if line =~ /^\s\s/ 
      if line =~ /^Number of files/
        stats << line
      elsif line =~ /^rsync:/
        messages << line
      elsif line =~ /^rsync error/
        errors << line
      else
        # file
        files << line
      end
    end
    { :messages => messages, :files => files, :stats => stats, :errors => errors }
  end

end    # / module RBack







