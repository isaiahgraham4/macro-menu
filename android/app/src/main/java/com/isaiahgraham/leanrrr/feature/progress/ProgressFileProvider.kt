package com.isaiahgraham.leanrrr.feature.progress

import androidx.core.content.FileProvider

/** Its own class so the manifest can hold it beside Meal's share-card provider (two providers can't share a class name). */
class ProgressFileProvider : FileProvider()
