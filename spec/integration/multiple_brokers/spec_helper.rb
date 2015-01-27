require 'spec_helper'

require 'test_cluster'

class ThreeBrokerCluster
  def initialize(properties = {})
    @zookeeper = ZookeeperRunner.new
    @brokers = (9092..9094).map { |port| BrokerRunner.new(port - 9092, port,
                                                          3,
                                                          2,
                                                          properties) }
  end

  def start
    @zookeeper.start
    @brokers.each(&:start)
    SPEC_LOGGER.info "Waiting on cluster"
    sleep 2
  end

  def stop
    SPEC_LOGGER.info "Stopping three broker cluster"
    SPEC_LOGGER.info "Stopping brokers"
    @brokers.each(&:stop)

    SPEC_LOGGER.info "Stopping ZK"
    @zookeeper.stop
  end

  def stop_first_broker
    SPEC_LOGGER.info "Stopping first broker"
    @brokers.first.stop
  end

  def start_first_broker
    SPEC_LOGGER.info "Starting first broker"
    @brokers.first.start
  end
end

RSpec.configure do |config|
  config.before(:each) do
    JavaRunner.remove_tmp
    JavaRunner.set_kafka_path!
  end
end
