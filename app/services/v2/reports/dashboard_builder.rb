# One payload for the management dashboard (Relatórios > Painel): the ad
# funnel by ad, by agent and new vs returning customer (V2::Reports::AdLeadsBuilder), the live queue and
# the per-agent table, all for the same period, conversion label and risk
# threshold.
class V2::Reports::DashboardBuilder
  include V2::Reports::DashboardScopes

  pattr_initialize [:account!, :params!]

  def build
    {
      funnel: {
        by_ad: V2::Reports::AdLeadsBuilder.new(account: account, params: params).build,
        by_agent: V2::Reports::AdLeadsBuilder.new(account: account, params: params.merge(group_by: 'agent')).build,
        by_customer: V2::Reports::AdLeadsBuilder.new(account: account, params: params.merge(group_by: 'customer')).build
      },
      queue: V2::Reports::QueueBuilder.new(account: account, params: params).build,
      agents: V2::Reports::AgentPerformanceBuilder.new(account: account, params: params).build,
      risk_minutes: risk_minutes,
      conversion_label: conversion_label
    }
  end
end
