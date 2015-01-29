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

class Pfctl
  class << self
    def test_sudo_pfctl
      res = `sudo -n pfctl -sa 2>&1`
      return res.include? "INFO"
    end

    def enable_pfctl
      SPEC_LOGGER.info "Enabling pfctl."
      system "sudo -n pfctl -e > /dev/null 2>&1"
    end

    def unblock_ports
      SPEC_LOGGER.info "Unblocking ports."
      system "sudo -n pfctl -f /etc/pf.conf > /dev/null 2>&1"
    end

    def block_port(port)
      SPEC_LOGGER.info "Blocking TCP on port #{port}."
      system "(sudo -n pfctl -sr 2>/dev/null; echo 'block drop quick on { en0 lo0 } proto tcp from any to any port = #{port}') | sudo -n pfctl -f - > /dev/null 2>&1"
    end
  end
end

def broker_string(broker)
  "#{broker.host}:#{broker.port}"
end

def not_blocked(brokers, blocked)
  all = brokers.keys
  all.delete blocked.id
  brokers[all.first]
end

def block_leader(broker_str, cluster_metadata)
  broker = ""

  # simulate graceful shutdown of the machine
  BrokerPool.open("test_client", [broker_str], 100) do |broker_pool|
    cluster_metadata.update(broker_pool.fetch_metadata([topic]))
    broker_pool.update_known_brokers(cluster_metadata.brokers)
    broker = cluster_metadata.lead_broker_for_partition(topic, 0)
    # first stop the broker - Kafka will move the leader
    @brokers[broker.id].stop
    # block communication with the broker
    Pfctl.block_port broker.port
  end

  broker
end

RSpec.configure do |config|
  if !Pfctl.test_sudo_pfctl then
    puts "Unable to execute 'sudo pfctl'. Some tests disabled."
    puts "Add the following to /etc/sudoers USING VISUDO!:"
    puts "#{`whoami`.strip}\tALL=NOPASSWD:\t/sbin/pfctl *"

    config.filter_run_excluding :requires => :sudo_pfctl
  end

  config.before(:each) do
    JavaRunner.remove_tmp
    JavaRunner.set_kafka_path!
  end
end
