#pragma once

#include <optional>
#include <string>

namespace flightsim_aide {

/// A Microsoft Flight Simulator variable, as a checklist writes it (the text
/// between the quotes of a quoted dataref name; D-85, D-86).
///
///   A:ELECTRICAL MASTER BATTERY:1, bool   a simulation variable, optional
///                                         index after the name, unit after the
///                                         comma (default `number`)
///   L:ELECTRICAL_Switch_BATTERY_Bus_1     a local variable of the aircraft's
///                                         own code (unit default `number`)
///   B:ELECTRICAL_BATTERY_2                an input event (a number)
///   Z:SWS_EXIT_PassengerDoor_Handle       a variable private to the aircraft
///                                         model (unit default `number`), read
///                                         like an L-variable
///
/// The prefix is case-insensitive. Pure string work; it never asks the sim.
struct MsfsVar {
  enum class Kind { simVar, localVar, inputEvent, zVar };
  Kind kind = Kind::simVar;
  /// What SimConnect is given as the datum name: `NAME` or `NAME:1` for an
  /// A-variable, `L:NAME` for an L-variable, `Z:NAME` for a Z-variable, the
  /// event name for a B-variable.
  std::string datum;
  /// The unit, empty for an input event.
  std::string unit;

  /// The same variable written two ways has the same key: the kind, the datum
  /// and the unit in lower case (names are case-insensitive, D-86).
  std::string key() const;
};

/// Reads [name]; nothing when it is not one of the four forms or is
/// malformed (no name, a comma in a B-variable, a second comma, a control
/// character, a bad index).
std::optional<MsfsVar> parseMsfsName(const std::string& name);

}  // namespace flightsim_aide
