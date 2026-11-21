package com.isaiahgraham.leanrrr.feature.health

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrBackground
import com.isaiahgraham.leanrrr.ui.theme.LeanrTheme
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * What Leanrrr does with Health Connect data, shown when someone taps the privacy link on Health Connect's permission screen
 * (required by Health Connect). The words follow the Apple Health section of the privacy policy.
 */
class HealthRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LeanrTheme {
                LeanrBackground {
                    LeanrScreen("Health Connect", onBack = { finish() }, showSettings = false) {
                        val paragraphs = listOf(
                            "Leanrrr only uses Health Connect if you connect it in Settings, and you choose which types it may read or write. If you connect:",
                            "• Leanrrr writes the food you log, the water you log (one total for each day) and the weights you enter.",
                            "• Leanrrr reads your weight, active energy (your calories burnt) and steps to show your trend, your steps and your calories burnt, and to estimate your target. Step counts and calories burnt are held in memory while you use Leanrrr, and the last week’s figures are shown in Leanrrr’s Steps and Calories burnt widgets on this phone. These figures are never saved in Leanrrr’s data, its backup or its exports.",
                            "Health information is never used for advertising or marketing, never sold, and never leaves your phone.",
                            "To choose exactly what Leanrrr can read or write, open Health Connect → App permissions → Leanrrr. Settings → Delete all my data can also remove the food, water and weights Leanrrr saved to Health Connect.",
                        )
                        item {
                            LeanrSection {
                                paragraphs.forEach { Text(it, style = LeanrType.body, color = Leanr.colours.text, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
                            }
                        }
                    }
                }
            }
        }
    }
}
