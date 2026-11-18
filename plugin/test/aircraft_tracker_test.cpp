#include "aircraft_tracker.h"
#include "doctest.h"

using namespace flightsim_aide;
using Phase = AircraftTracker::Phase;

namespace {

constexpr int64_t kS = AircraftTracker::kSettleMs;

// A tracker connected at t=0 with the PC-12 read and settled.
AircraftTracker ready() {
  AircraftTracker t;
  t.onConnected(0);
  t.onIdentity("PC12", "Fly7", 100);
  t.tick(kS + 10);
  REQUIRE(t.available());
  return t;
}

}  // namespace

TEST_CASE("a tracker that was never connected is disconnected and reports nothing") {
  AircraftTracker t;
  CHECK(t.phase() == Phase::disconnected);
  CHECK_FALSE(t.available());
  t.onSimStop(0);
  t.onIdentity("PC12", "x", 10);
  CHECK_FALSE(t.tick(100000).ready);
}

TEST_CASE("connecting mid-flight: held back for the settle time, then ready without a bump") {
  AircraftTracker t;
  t.onConnected(1000);
  CHECK(t.wantsIdentity());
  CHECK(t.phase() == Phase::loading);
  t.onIdentity("PC12", "Fly7 OH-DEN", 1100);
  CHECK_FALSE(t.tick(1000 + kS - 1).ready);
  const auto u = t.tick(1000 + kS);
  CHECK(u.ready);
  CHECK_FALSE(u.bump);
  CHECK(t.available());
  CHECK(t.identity().model == "PC12");
  CHECK(t.identity().title == "Fly7 OH-DEN");
}

TEST_CASE("without an identity there is nothing to publish") {
  AircraftTracker t;
  t.onConnected(0);
  CHECK_FALSE(t.tick(kS + 100).ready);
  CHECK_FALSE(t.available());
}

TEST_CASE("a flight reload of the same aircraft bumps once, after SimStart, AircraftLoaded and the settle time") {
  AircraftTracker t = ready();
  t.onSimStop(10000);
  CHECK_FALSE(t.available());
  t.onSimStart(10700);
  t.onIdentity("PC12", "Fly7", 11000);  // before AircraftLoaded: not fresh yet
  CHECK_FALSE(t.tick(12000).ready);
  t.onAircraftLoaded("c:/pkg/aircraft.cfg", 13300);
  CHECK(t.wantsIdentity());
  CHECK_FALSE(t.tick(13400).ready);
  t.onIdentity("PC12", "Fly7", 13500);
  CHECK_FALSE(t.tick(13300 + kS - 1).ready);
  const auto u = t.tick(13300 + kS);
  CHECK(u.ready);
  CHECK(u.bump);
  CHECK(t.identity().path == "c:/pkg/aircraft.cfg");
  // Nothing more to say afterwards.
  CHECK_FALSE(t.tick(20000).ready);
}

TEST_CASE("another aircraft: the new identity is published with one bump") {
  AircraftTracker t = ready();
  t.onSimStop(10000);
  t.onSimStart(10200);
  t.onIdentity("ATCCOM.AC_MODEL C152.0.text", "Cessna C152", 10500);
  t.onAircraftLoaded("c:/c152/aircraft.cfg", 13000);
  t.onIdentity("ATCCOM.AC_MODEL C152.0.text", "Cessna C152", 13100);
  const auto u = t.tick(13000 + kS);
  CHECK(u.ready);
  CHECK(u.bump);
  CHECK(t.identity().model == "ATCCOM.AC_MODEL C152.0.text");
}

TEST_CASE("a title change with no load event is a load (a livery change)") {
  AircraftTracker t = ready();
  t.onIdentity("PC12", "Fly7", 5000);  // unchanged: nothing happens
  CHECK(t.available());
  t.onIdentity("PC12", "Tradewind", 6000);
  CHECK_FALSE(t.available());
  CHECK_FALSE(t.tick(6000 + kS - 1).ready);
  const auto u = t.tick(6000 + kS);
  CHECK(u.ready);
  CHECK(u.bump);
  CHECK(t.identity().title == "Tradewind");
}

TEST_CASE("an AircraftLoaded in the ready phase starts a load too") {
  AircraftTracker t = ready();
  t.onAircraftLoaded("c:/other/aircraft.cfg", 5000);
  CHECK_FALSE(t.available());
  t.onIdentity("PC12", "Fly7", 5100);
  const auto u = t.tick(5000 + kS);
  CHECK(u.ready);
  CHECK(u.bump);
}

TEST_CASE("several triggers in one load give one bump") {
  AircraftTracker t = ready();
  t.onSimStop(10000);
  t.onSimStart(10100);
  t.onAircraftLoaded("p", 12000);
  t.onIdentity("PC12", "A", 12100);
  t.onAircraftLoaded("p", 12500);  // again
  t.onIdentity("PC12", "A", 12600);
  CHECK(t.tick(12500 + kS).bump);
  CHECK_FALSE(t.tick(30000).ready);
}

TEST_CASE("on the main menu (no SimStart) nothing is reported, however long it takes") {
  AircraftTracker t = ready();
  t.onSimStop(10000);
  CHECK_FALSE(t.tick(10000 + AircraftTracker::kLoadTimeoutMs * 10).ready);
  CHECK_FALSE(t.available());
}

TEST_CASE("a sim that never sends AircraftLoaded is ready after the load timeout") {
  AircraftTracker t = ready();
  t.onSimStop(10000);
  t.onSimStart(10100);
  t.onIdentity("PC12", "Fly7", 10200);
  CHECK_FALSE(t.tick(10100 + AircraftTracker::kLoadTimeoutMs - 1).ready);
  const auto u = t.tick(10100 + AircraftTracker::kLoadTimeoutMs);
  CHECK(u.ready);
  CHECK(u.bump);
}

TEST_CASE("the tracker asks for the identity once per trigger") {
  AircraftTracker t = ready();
  t.identityRequested();
  CHECK_FALSE(t.wantsIdentity());
  t.onAircraftLoaded("p", 5000);
  CHECK(t.wantsIdentity());
  t.identityRequested();
  CHECK_FALSE(t.wantsIdentity());
}

TEST_CASE("after a disconnect events are ignored until the next connection") {
  AircraftTracker t = ready();
  t.onDisconnected();
  CHECK(t.phase() == Phase::disconnected);
  CHECK_FALSE(t.available());
  t.onSimStop(1);
  t.onAircraftLoaded("p", 2);
  CHECK(t.phase() == Phase::disconnected);
  t.onConnected(100);
  CHECK(t.phase() == Phase::loading);
}

TEST_CASE("pause is not a load: nothing in the tracker reacts to it") {
  AircraftTracker t = ready();
  CHECK(t.available());
  CHECK_FALSE(t.tick(50000).ready);
  CHECK(t.available());
}
