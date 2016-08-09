module Bureaucrat

  @@class_callbacks = {}
  @@instance_callbacks = {}
  @@callback_queue = Queue.new

  unless defined? @@callback_thread
    @@callback_thread = Thread.new do
      while true
        sleep 0.10 # stop and breathe
        while !@@callback_queue.empty?
          source, result, method = @@callback_queue.pop
          self.exec_callbacks(source, result, method)
        end
        break if defined? @@its_5oclock_somewhere
      end
    end

    @@callback_thread.priority = Thread.current.priority - 1

    at_exit do
      send_msg = @@callback_queue.length > 0
      if send_msg
        cb_msg = @@callback_queue.length == 1 ? "1 callback" : "#{@@callback_queue.length} callbacks"
        warn "Bureaucrat callback thread finishing #{cb_msg} before exit"
      end
      @@its_5oclock_somewhere = true
      @@callback_thread.join
    end
  end

  def self.callbacks
    [:console]
  end

  def self.add_class_callback(classmethod, callback, cbparams=nil)
    self.add_callback(classmethod, :class, callback, cbparams)
  end

  def self.add_instance_callback(classmethod, callback, cbparams=nil)
    self.add_callback(classmethod, :instance, callback, cbparams)
  end

  def self.dump_callbacks
    {:class_callbacks => @@class_callbacks, :instance_callbacks => @@instance_callbacks}.inspect
  end

  def self.included(clazz)
    clazz.define_singleton_method(:Bureaucrat) do
      Class.new(clazz) do
        define_singleton_method(:new) do |*args|
          self.superclass.new(*args).bureaucrat
        end
        (clazz.singleton_methods - Object.singleton_methods).each do |method|
          define_singleton_method(method) do |*args|
            result = super(*args)
            Bureaucrat.queue_callbacks(clazz, result.clone, method.to_s)
            result
          end
        end
      end
    end
  end

  def bureaucrat
    raise 'public reinit_params undefined for class ' + self.class.to_s unless self.respond_to?(:reinit_params)
    Class.new(self.class) do
      (self.instance_methods - Object.instance_methods).each do |mname|
        define_method(mname) do |*args|
          result = super(*args)
          Bureaucrat.queue_callbacks(self.clone, result.clone, mname.to_s)
          result
        end
      end
    end.new(*reinit_params)
  end

  private

  def self.queue_callbacks(source, result, method)
    @@callback_queue.push([source, result, method])
  end

  def self.exec_callbacks(source, result, srcmethod)
    if source.class == Class
      classmethod = "#{source}.#{srcmethod}"
      return if @@class_callbacks[classmethod].nil?
      @@class_callbacks[classmethod].each do |cb| # e.g. [:console, "console text preface"]
        self.method(cb[0]).call(cb[1], result)
      end
    else
      classmethod = "#{source.class.superclass}.#{srcmethod}"
      return if @@instance_callbacks[classmethod].nil?
      @@instance_callbacks[classmethod].each do |cb| # e.g. [:console, "console text preface"]
        self.method(cb[0]).call(cb[1], result, source)
      end
    end
  end

  def self.add_callback(classmethod, scope, callback, cbparams=nil)
    raise "nil callback scope is not availabe, use :instance or :class" if scope.nil?
    raise "callback scope :#{scope} is not available, use :instance or :class" unless scope == :class || scope == :instance
    raise "callback :#{callback} is not available" unless self.callbacks.include?(callback)

    callbacks = scope == :class ? @@class_callbacks : @@instance_callbacks
    callbacks[classmethod] = [] if callbacks[classmethod].nil?
    callbacks[classmethod] << [callback, cbparams]
  end

  def self.console(cbparams, result, source=nil)
    console = "** #{cbparams}: "
    console += result.nil? ? "nil result" : "\"#{result}\""
    console += " from \"#{source}\"" unless source.nil?
    puts console
  end

end

