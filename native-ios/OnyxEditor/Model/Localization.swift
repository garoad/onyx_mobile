// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Looks up a string that is only known at run time (OnyxKit's control titles, picker options, help texts) in the String Catalog; the English text is the key and the fallback.
func L(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: nil) }
