//
//  TeamDashboardView.swift
//  FTCTeamHub
//
//  A full, detailed dashboard for any single FTC team — your own team or a
//  bookmarked opponent. Pulls multi-season OPR trends, full event history,
//  and per-event alliance-partner frequency from the live FTCScout API.
//  This is the "much more detailed, sophisticated" team view, replacing
//  the flatter single-season card from the previous Live Data tab.
//

import SwiftUI
import Charts

struct TeamDashboardView: View {
    let teamNumber: Int
    let teamName: String
    let season: Int
    let api: FTCScoutAPIServicing

    @State private var seasonHistory: [FTCSeasonStat] = []
    @State private var eventsAttended: [FTCEventAttended] = []
    @State private var isLoadingHistory = true
    @State private var isLoadingEvents = true
    @State private var historyError: String?
    @State private var eventsError: String?

    private var seasonsToFetch: [Int] { Array((season - 4)...season) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                statCardsRow

                GroupBox("OPR Trend by Season") {
                    if isLoadingHistory {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                    } else if let historyError {
                        ContentUnavailableView {
                            Label("OPR history unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(historyError)
                        } actions: {
                            Button("Retry") { Task { await loadHistory() } }
                        }
                    } else if seasonHistory.isEmpty {
                        Text("No historical data available for this team.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        Chart {
                            ForEach(seasonHistory) { stat in
                                LineMark(x: .value("Season", "\(stat.season)"), y: .value("OPR", stat.totalOPR))
                                    .symbol(.circle)
                                PointMark(x: .value("Season", "\(stat.season)"), y: .value("OPR", stat.totalOPR))
                            }
                        }
                        .frame(height: 200)
                        .padding(.top, 8)
                    }
                }

                GroupBox("Events Attended") {
                    if isLoadingEvents {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                    } else if let eventsError {
                        ContentUnavailableView {
                            Label("Event history unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(eventsError)
                        } actions: {
                            Button("Retry") { Task { await loadEvents() } }
                        }
                    } else if eventsAttended.isEmpty {
                        Text("FTCScout returned no event history for the \(season) season.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(eventsAttended.enumerated()), id: \.element.id) { index, attended in
                                NavigationLink {
                                    AlliancePartnersView(teamNumber: teamNumber, event: attended.event, season: season, api: api)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(attended.event.name).font(.subheadline.weight(.medium))
                                            Text("\(attended.event.start) – \(attended.event.end)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)

                                if index < eventsAttended.count - 1 { Divider() }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(teamName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
        .task { await loadEvents() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(teamName).font(.title2.bold())
            Text("Team \(teamNumber)").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var statCardsRow: some View {
        HStack(spacing: 10) {
            StatCard(title: "Latest OPR", value: seasonHistory.max(by: { $0.season < $1.season }).map { String(format: "%.1f", $0.totalOPR) } ?? "—")
            StatCard(title: "Seasons Tracked", value: "\(seasonHistory.count)")
            StatCard(title: "Events (\(season))", value: "\(eventsAttended.count)")
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        historyError = nil
        do {
            seasonHistory = try await api.fetchSeasonHistory(teamNumber: teamNumber, seasons: seasonsToFetch)
        } catch {
            historyError = error.localizedDescription
        }
        isLoadingHistory = false
    }

    private func loadEvents() async {
        isLoadingEvents = true
        eventsError = nil
        do {
            eventsAttended = try await api.fetchEventsAttended(teamNumber: teamNumber, season: season)
        } catch {
            eventsError = error.localizedDescription
        }
        isLoadingEvents = false
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Alliance partner frequency for a specific event

private struct AlliancePartnersView: View {
    let teamNumber: Int
    let event: FTCEventSummary
    let season: Int
    let api: FTCScoutAPIServicing

    @State private var partners: [FTCAlliancePartner] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Alliance data unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await loadPartners() } }
                }
            } else if partners.isEmpty {
                ContentUnavailableView("No alliance data", systemImage: "person.2",
                                       description: Text("No match data was returned for this event yet."))
            } else {
                Section("Played alongside") {
                    ForEach(partners) { partner in
                        HStack {
                            Text("Team \(partner.teamNumber)")
                            Spacer()
                            Text("\(partner.matchesTogether) match\(partner.matchesTogether == 1 ? "" : "es")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPartners() }
    }

    private func loadPartners() async {
        isLoading = true
        errorMessage = nil
        do {
            partners = try await api.fetchAlliancePartners(teamNumber: teamNumber, eventCode: event.code, season: season)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
