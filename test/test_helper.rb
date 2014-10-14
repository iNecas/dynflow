require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/spec'

if ENV['RM_INFO']
  require 'minitest/reporters'
  MiniTest::Reporters.use!
end

load_path = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH << load_path unless $LOAD_PATH.include? load_path

require 'dynflow'
require 'dynflow/testing'
require 'pry'

require 'support/code_workflow_example'
require 'support/middleware_example'
require 'support/rescue_example'
require 'support/dummy_example'

class TestExecutionLog

  include Enumerable

  def initialize
    @log = []
  end

  def <<(action)
    @log << [action.class, action.input]
  end

  def log
    @log
  end

  def each(&block)
    @log.each(&block)
  end

  def size
    @log.size
  end

  def self.setup
    @run, @finalize = self.new, self.new
  end

  def self.teardown
    @run, @finalize = nil, nil
  end

  def self.run
    @run || []
  end

  def self.finalize
    @finalize || []
  end

end

# To be able to stop a process in some step and perform assertions while paused
class TestPause

  def self.setup
    @pause = Dynflow::Future.new
    @ready = Dynflow::Future.new
  end

  def self.teardown
    @pause = nil
    @ready = nil
  end

  # to be called from action
  def self.pause
    if !@pause
      raise 'the TestPause class was not setup'
    elsif @ready.ready?
      raise 'you can pause only once'
    else
      @ready.resolve(true)
      @pause.wait
    end
  end

  # in the block perform assertions
  def self.when_paused
    if @pause
      @ready.wait # wait till we are paused
      yield
      @pause.resolve(true) # resume the run
    else
      raise 'the TestPause class was not setup'
    end
  end
end

module WorldInstance
  def self.world
    @world ||= create_world(:isolated => false)
  end

  def self.logger_adapter
    @adapter ||= Dynflow::LoggerAdapters::Simple.new $stderr, 4
  end

  # @param isolated [boolean] - if the adapter is not shared between two test runs: we clear
  #   the worlrs register there every run to avoid collisions
  def self.persistence_adapter(isolated = true)
    db_config =     if isolated
                      db_config = ENV['DB_CONN_STRING'] || 'sqlite:/'
                      @isolated_adapter ||= Dynflow::PersistenceAdapters::Sequel.new(db_config)
                    else
                      Dynflow::PersistenceAdapters::Sequel.new('sqlite:/')
                    end
  end

  def self.create_world(options = {})
    isolated = options.key?(:isolated) ? options.delete(:isolated) : true
    options = { pool_size: 5,
                persistence_adapter: persistence_adapter(isolated),
                transaction_adapter: Dynflow::TransactionAdapters::None.new,
                logger_adapter: logger_adapter,
                auto_rescue: false }.merge(options)
    Dynflow::World.new(options).tap do |world|
      if isolated
        @isolated_worlds ||= []
        @isolated_worlds << world
      end
    end
  end

  def self.clean_worlds_register
    persistence_adapter = WorldInstance.persistence_adapter(true)
    persistence_adapter.find_worlds({}).each do |w|
      warn "Unexpected world in the regiter: #{ w[:id] }"
      persistence_adapter.pull_envelopes(w[:id])
      persistence_adapter.delete_executor_allocations(world_id: w[:id])
      persistence_adapter.delete_world(w[:id])
    end
  end

  def self.terminate_isolated
    return unless @isolated_worlds
    @isolated_worlds.map(&:terminate).map(&:wait)
    @isolated_worlds.clear
  end

  def self.terminate_shared
    @world.terminate.wait if @world
    @world = nil
  end

  def world
    WorldInstance.world
  end
end

class MiniTest::Test
  def setup
    WorldInstance.clean_worlds_register
  end

  def teardown
    WorldInstance.terminate_isolated
  end
end

# ensure there are no unresolved Futures at the end or being GCed
future_tests =-> do
  future_creations  = {}
  non_ready_futures = {}

  # monkey-patch to get the name of current test for tracking futures creation
  module TestNameTracking
    class << self
      attr_accessor :current_name
    end
    def run_with_tracking
      TestNameTracking.current_name = self.name
      run_without_tracking
    ensure
      TestNameTracking.current_name = nil
    end

    def self.included(base)
      base.class_eval do
        alias_method :run_without_tracking, :run
        alias_method :run, :run_with_tracking
      end
    end
  end

  class MiniTest::Test
    include TestNameTracking
  end

  Dynflow::Future.singleton_class.send :define_method, :new do |*args, &block|
    super(*args, &block).tap do |f|
      future_creations[f.object_id]  = { backtrace: caller(4),
                                         test_name: TestNameTracking.current_name }
      non_ready_futures[f.object_id] = true
    end
  end

  delete_barrier = Mutex.new

  set_method = Dynflow::Future.instance_method :set
  Dynflow::Future.send :define_method, :set do |*args|
    begin
      set_method.bind(self).call *args
    ensure
      delete_barrier.synchronize do
        non_ready_futures.delete self.object_id
      end
    end
  end

  MiniTest.after_run do
    WorldInstance.terminate_shared
    unless non_ready_futures.empty?
      unified = non_ready_futures.each_with_object({}) do |(id, _), h|
        backtrace_first    = future_creations[id][:backtrace][0]
        h[backtrace_first] ||= []
        h[backtrace_first] << id
      end
      info = unified.map do |backtrace, ids|
        futures_info = ids.map do |id|
          creation_info = future_creations[id]
          "#{id} (#{creation_info[:test_name]})"
        end.join(', ')
        "--- #{futures_info}\n#{future_creations[ids.first][:backtrace].join("\n")}"
      end.join("\n")

      raise("there were #{non_ready_futures.size} non_ready_futures:\n" + info)
    end
  end

  # time out all futures by default
  default_timeout = 8
  wait_method     = Dynflow::Future.instance_method(:wait)

  Dynflow::Future.class_eval do
    define_method :wait do |timeout = nil|
      wait_method.bind(self).call(timeout || default_timeout)
    end
  end

end.call

module PlanAssertions

  def inspect_flow(execution_plan, flow)
    out = ""
    inspect_subflow(out, execution_plan, flow, "")
    out
  end

  def inspect_plan_steps(execution_plan)
    out = ""
    inspect_plan_step(out, execution_plan, execution_plan.root_plan_step, "")
    out
  end

  def assert_planning_success(execution_plan)
    plan_steps = execution_plan.steps.values.find_all do |step|
      step.is_a? Dynflow::ExecutionPlan::Steps::PlanStep
    end
    plan_steps.all? { |plan_step| plan_step.state.must_equal :success, plan_step.error }
  end

  def assert_run_flow(expected, execution_plan)
    assert_planning_success(execution_plan)
    inspect_flow(execution_plan, execution_plan.run_flow).chomp.must_equal dedent(expected).chomp
  end

  def assert_finalize_flow(expected, execution_plan)
    assert_planning_success(execution_plan)
    inspect_flow(execution_plan, execution_plan.finalize_flow).chomp.must_equal dedent(expected).chomp
  end

  def assert_run_flow_equal(expected_plan, execution_plan)
    expected = inspect_flow(expected_plan, expected_plan.run_flow)
    current  = inspect_flow(execution_plan, execution_plan.run_flow)
    assert_equal expected, current
  end

  def assert_steps_equal(expected, current)
    current.id.must_equal expected.id
    current.class.must_equal expected.class
    current.state.must_equal expected.state
    current.action_class.must_equal expected.action_class
    current.action_id.must_equal expected.action_id

    if expected.respond_to?(:children)
      current.children.must_equal(expected.children)
    end
  end

  def assert_plan_steps(expected, execution_plan)
    inspect_plan_steps(execution_plan).chomp.must_equal dedent(expected).chomp
  end

  def assert_finalized(action_class, input)
    assert_executed(:finalize, action_class, input)
  end

  def assert_executed(phase, action_class, input)
    log = TestExecutionLog.send(phase).log

    found_log = log.any? do |(logged_action_class, logged_input)|
      action_class == logged_action_class && input == logged_input
    end

    unless found_log
      message = ["#{action_class} with input #{input.inspect} not executed in #{phase} phase"]
      message << "following actions were executed:"
      log.each do |(logged_action_class, logged_input)|
        message << "#{logged_action_class} #{logged_input.inspect}"
      end
      raise message.join("\n")
    end
  end

  def inspect_subflow(out, execution_plan, flow, prefix)
    case flow
    when Dynflow::Flows::Atom
      out << prefix
      out << flow.step_id.to_s << ': '
      step = execution_plan.steps[flow.step_id]
      out << step.action_class.to_s[/\w+\Z/]
      out << "(#{step.state})"
      out << ' '
      action = execution_plan.world.persistence.load_action(step)
      out << action.input.inspect
      unless step.state == :pending
        out << ' --> '
        out << action.output.inspect
      end
      out << "\n"
    else
      out << prefix << flow.class.name << "\n"
      flow.sub_flows.each do |sub_flow|
        inspect_subflow(out, execution_plan, sub_flow, prefix + '  ')
      end
    end
    out
  end

  def inspect_plan_step(out, execution_plan, plan_step, prefix)
    out << prefix
    out << plan_step.action_class.to_s[/\w+\Z/]
    out << "\n"
    plan_step.children.each do |sub_step_id|
      sub_step = execution_plan.steps[sub_step_id]
      inspect_plan_step(out, execution_plan, sub_step, prefix + '  ')
    end
    out
  end

  def dedent(string)
    dedent = string.scan(/^ */).map { |spaces| spaces.size }.min
    string.lines.map { |line| line[dedent..-1] }.join
  end
end
