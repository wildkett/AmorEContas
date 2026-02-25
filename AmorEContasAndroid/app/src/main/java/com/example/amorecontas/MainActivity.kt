package com.example.AmorEContas

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AmorEContasApp()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AmorEContasApp() {
    Scaffold(
        topBar = {
            TopAppBar(title = { Text(stringResource(id = R.string.app_name)) }, actions = {
                // Add button
                Button(onClick = { /* navigate to add expense */ }) {
                    Icon(Icons.Default.Add, contentDescription = stringResource(R.string.addexpense_button))
                }

                // Settings button
                Button(onClick = { /* navigate to settings */ }) {
                    Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings_section_title))
                }
            })
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(16.dp)) {
            Text(text = stringResource(R.string.summary_section_title), style = MaterialTheme.typography.titleLarge)
            Text(text = stringResource(R.string.summary_total))

            // Quick actions
            Button(onClick = { /* open AddExpenseActivity */ }, modifier = Modifier.padding(top = 16.dp)) {
                Text(text = stringResource(R.string.addexpense_button))
            }

            Button(onClick = { /* open SettingsActivity */ }, modifier = Modifier.padding(top = 8.dp)) {
                Text(text = stringResource(R.string.settings_nav_title))
            }
        }
    }
}
