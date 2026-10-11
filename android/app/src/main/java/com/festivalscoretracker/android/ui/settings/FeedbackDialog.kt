package com.festivalscoretracker.android.ui.settings

import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Size
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackCopy
import com.festivalscoretracker.android.core.feedback.FeedbackDraft
import com.festivalscoretracker.android.core.feedback.FeedbackLimits
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.feedback.feedbackEnabled
import com.festivalscoretracker.android.data.feedback.feedbackStatus
import com.festivalscoretracker.android.data.feedback.submitFeedback
import com.festivalscoretracker.android.presentation.feedback.FeedbackFormState
import com.festivalscoretracker.android.presentation.feedback.FeedbackPhase
import com.festivalscoretracker.android.presentation.feedback.FeedbackViewModel
import com.festivalscoretracker.android.ui.common.CoversBackdrop
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalModalBody
import com.festivalscoretracker.android.ui.common.FestivalModalHeader
import com.festivalscoretracker.android.ui.common.festivalSheetHingeSide
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.io.FileNotFoundException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// region Wiring

/**
 * The Settings feedback view model, sending through the shared keyless gate and reading
 * picked media with the content resolver (no copies, no storage permission).
 *
 * @param api Shared API client.
 * @return View model scoped to the Settings destination.
 */
@Composable
fun rememberFeedbackViewModel(api: FestivalApi): FeedbackViewModel {
    val resolver = LocalContext.current.applicationContext.contentResolver
    return viewModel {
        FeedbackViewModel(
            send = { submission ->
                api.submitFeedback(submission) { attachment ->
                    resolver.openInputStream(Uri.parse(attachment.id)) ?: throw FileNotFoundException(attachment.name)
                }
            },
            status = { id -> api.feedbackStatus(id) },
            features = { api.feedbackEnabled() },
            appVersion = BuildConfig.VERSION_NAME,
            clientInfo = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}); ${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }
}

// endregion

// region Dialog

/**
 * Report an Issue / Request a Feature (issue #78): an M3 full-screen dialog on compact windows
 * and a centred dialog on wider ones. Labelled fields keep a visible helper line under each box
 * (placeholders vanish while typing). Close, Back and the discard confirmation guard unsent input.
 *
 * @param viewModel Form state and actions.
 */
@Composable
fun FeedbackDialogHost(viewModel: FeedbackViewModel) {
    val state by viewModel.form.collectAsStateWithLifecycle()
    val sent by viewModel.sent.collectAsStateWithLifecycle()
    // The result only ever shows after the form has closed (issue #565, modal-shell R7).
    sent?.let { result ->
        FestivalAlertDialog(
            title = result.title,
            text = result.message,
            tag = "fst.settings.feedback.sent",
            textTag = "fst.settings.feedback.sent.message",
            confirmLabel = "Done",
            confirmTag = "fst.settings.feedback.done",
            onConfirm = viewModel::dismissSent,
            onDismissRequest = viewModel::dismissSent,
        )
    }
    val form = state ?: return
    // On a separating fold the form keeps to one side of the hinge, like the shared sheets (M3:
    // "Never place interactive content or critical information across the hinge area"). Read it
    // from the activity window: inside the new dialog window the root width is still 0 (issue #146).
    val hingeSide = Modifier.festivalSheetHingeSide()
    // The form is the modal-shell R6 exception (its own Dialog), so it registers itself: the
    // backdrop and page motion kept animating unseen behind the full-screen form (issue #186).
    CoversBackdrop {
        Dialog(
            onDismissRequest = viewModel::requestClose,
            properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false, decorFitsSystemWindows = false),
        ) {
            BackHandler(onBack = viewModel::requestClose)
            BoxWithConstraints(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize().then(hingeSide).systemBarsPadding().imePadding(),
            ) {
                val compact = !AdaptiveLayoutPolicy.isRegularWidth(maxWidth.value.toInt())
                Surface(
                    shape = if (compact) RectangleShape else MaterialTheme.shapes.extraLarge,
                    color = BrandTokens.cardBackground,
                    modifier = Modifier
                        .then(if (compact) Modifier.fillMaxSize() else Modifier.padding(24.dp).widthIn(max = 640.dp).fillMaxWidth())
                        .popupTestTags()
                        .testTag("fst.settings.feedback.dialog")
                        .semantics { paneTitle = form.draft.kind.formTitle },
                ) {
                    FeedbackForm(form, viewModel)
                }
            }
            if (form.confirmingDiscard) {
                val noun = form.draft.kind.noun
                FestivalAlertDialog(
                    title = "Discard this $noun?",
                    text = if (form.phase == FeedbackPhase.Submitting) {
                        "Sending will stop and everything you entered will be lost."
                    } else {
                        "Your text and attachments will be lost."
                    },
                    tag = "fst.settings.feedback.discard.dialog",
                    confirmLabel = "Discard",
                    confirmTag = "fst.settings.feedback.discard.confirm",
                    onConfirm = viewModel::confirmDiscard,
                    dismissLabel = "Keep Editing",
                    dismissTag = "fst.settings.feedback.discard.cancel",
                    onDismissRequest = viewModel::keepEditing,
                    destructive = true,
                )
            }
        }
    }
}

@Composable
private fun FeedbackForm(form: FeedbackFormState, viewModel: FeedbackViewModel) {
    val kind = form.draft.kind
    Column(Modifier.padding(top = 12.dp)) {
        FestivalModalHeader(
            title = kind.formTitle,
            closeTag = "fst.settings.feedback.close",
            onClose = viewModel::requestClose,
            titleTag = "fst.settings.feedback.title",
        ) {
            TextButton(
                onClick = viewModel::submit,
                enabled = form.canSubmit,
                modifier = Modifier.heightIn(min = 48.dp).testTag("fst.settings.feedback.submit"),
            ) { Text("Submit", fontWeight = FontWeight.Bold) }
        }
        FestivalModalBody {
            if (form.busy) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .padding(horizontal = 24.dp, vertical = 4.dp)
                        .testTag("fst.settings.feedback.progress")
                        .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
                ) {
                    // The app's one loading indicator (design/android.md), not the theme's blue primary.
                    // The status text says what is in progress; one TalkBack stop, not a separate progress bar.
                    Box(Modifier.clearAndSetSemantics {}) { FestivalLoading(label = null, size = 24.dp) }
                    Text(form.progressText, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium)
                }
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                EditingContent(form, viewModel)
            }
        }
    }
}

@Composable
private fun EditingContent(form: FeedbackFormState, viewModel: FeedbackViewModel) {
    val draft = form.draft
    val kind = draft.kind
    val enabled = form.editable
    form.error?.let { message ->
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(BrandTokens.statusRed.copy(alpha = 0.22f))
                .border(1.dp, BrandTokens.statusRed, RoundedCornerShape(12.dp))
                .padding(12.dp)
                .testTag("fst.settings.feedback.error")
                .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Assertive },
        ) {
            Icon(Icons.Filled.Error, contentDescription = "Error", tint = BrandTokens.textPrimary)
            Text(message, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium)
        }
    }
    // Submit stays disabled while invalid; say why next to it rather than only on a tap.
    form.validationMessage?.let { reason ->
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("fst.settings.feedback.validation")
                .semantics(mergeDescendants = true) {},
        ) {
            Icon(Icons.Outlined.Info, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.size(20.dp))
            Text(reason, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
        }
    }
    FeedbackField(
        label = FeedbackCopy.TITLE,
        help = FeedbackCopy.titleHelp(kind),
        value = draft.title,
        onChange = { value -> viewModel.edit { it.copy(title = value) } },
        enabled = enabled,
        tag = "fst.settings.feedback.field.title",
        singleLine = true,
        maxLength = FeedbackLimits.MAX_TITLE_LENGTH,
    )
    FeedbackField(
        label = FeedbackCopy.DESCRIPTION,
        help = FeedbackCopy.descriptionHelp(kind),
        value = draft.description,
        onChange = { value -> viewModel.edit { it.copy(description = value) } },
        enabled = enabled,
        tag = "fst.settings.feedback.field.description",
        minLines = 4,
    )
    if (kind.hasBugFields) {
        FeedbackField(
            label = FeedbackCopy.REPRO,
            help = FeedbackCopy.REPRO_HELP,
            value = draft.reproSteps,
            onChange = { value -> viewModel.edit { it.copy(reproSteps = value) } },
            enabled = enabled,
            tag = "fst.settings.feedback.field.repro",
            minLines = 3,
        )
        FeedbackField(
            label = FeedbackCopy.EXPECTED,
            help = FeedbackCopy.EXPECTED_HELP,
            value = draft.expectedBehavior,
            onChange = { value -> viewModel.edit { it.copy(expectedBehavior = value) } },
            enabled = enabled,
            tag = "fst.settings.feedback.field.expected",
            minLines = 2,
        )
    }
    AttachmentsSection(draft, form.notice, enabled, viewModel)
}

@Composable
private fun FeedbackField(
    label: String,
    help: String,
    value: String,
    onChange: (String) -> Unit,
    enabled: Boolean,
    tag: String,
    singleLine: Boolean = false,
    minLines: Int = 1,
    maxLength: Int = FeedbackLimits.MAX_TEXT_LENGTH,
) {
    OutlinedTextField(
        value = value,
        onValueChange = { onChange(if (singleLine) it.replace("\n", " ").take(maxLength) else it.take(maxLength)) },
        label = { Text(label) },
        supportingText = { Text(help) },
        enabled = enabled,
        singleLine = singleLine,
        minLines = minLines,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = BrandTokens.textPrimary,
            unfocusedTextColor = BrandTokens.textPrimary,
            focusedLabelColor = BrandTokens.textPrimary,
            unfocusedLabelColor = BrandTokens.textSecondary,
            focusedSupportingTextColor = BrandTokens.textSecondary,
            unfocusedSupportingTextColor = BrandTokens.textSecondary,
            focusedBorderColor = BrandTokens.accentBlue,
            unfocusedBorderColor = BrandTokens.textMuted,
            cursorColor = BrandTokens.textPrimary,
        ),
        modifier = Modifier.fillMaxWidth().testTag(tag),
    )
}

// endregion

// region Attachments

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AttachmentsSection(draft: FeedbackDraft, notice: String?, enabled: Boolean, viewModel: FeedbackViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var menuOpen by rememberSaveable { mutableStateOf(false) }
    var openFailure by remember { mutableStateOf<String?>(null) }
    val accept: (List<Uri>) -> Unit = { uris ->
        if (uris.isNotEmpty()) {
            scope.launch {
                val picked = withContext(Dispatchers.IO) { uris.map { describe(context.contentResolver, it) } }
                viewModel.addAttachments(picked)
            }
        }
    }
    val mediaPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(FeedbackLimits.MAX_ATTACHMENTS),
        accept,
    )
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), accept)

    Column(Modifier.fillMaxWidth().padding(top = 4.dp)) {
        Text(
            "Attachments",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
        Text(FeedbackCopy.ATTACH_HELP, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
        if (draft.attachments.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp).testTag("fst.settings.feedback.attachments"),
            ) {
                draft.attachments.forEach { attachment ->
                    AttachmentTile(
                        attachment = attachment,
                        enabled = enabled,
                        onOpen = {
                            openFailure = if (openUri(context, Uri.parse(attachment.id), attachment.mimeType)) null else "No app on this device can open ${attachment.name}."
                        },
                        onRemove = { viewModel.removeAttachment(attachment.id) },
                    )
                }
            }
        }
        (openFailure ?: notice)?.let { text ->
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                color = BrandTokens.textSecondary,
                modifier = Modifier
                    .padding(bottom = 8.dp)
                    .testTag("fst.settings.feedback.attachments.notice")
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
        Box {
            OutlinedButton(
                onClick = { menuOpen = true },
                enabled = enabled && draft.attachments.size < FeedbackLimits.MAX_ATTACHMENTS,
                modifier = Modifier.heightIn(min = 48.dp).testTag("fst.settings.feedback.attach"),
            ) {
                Icon(Icons.Filled.AttachFile, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
                Text(FeedbackCopy.ATTACH)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }, modifier = Modifier.popupTestTags()) {
                DropdownMenuItem(
                    text = { Text("Photos & Videos") },
                    leadingIcon = { Icon(Icons.Filled.Image, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        openFailure = null
                        mediaPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                    },
                    modifier = Modifier.testTag("fst.settings.feedback.attach.media"),
                )
                DropdownMenuItem(
                    text = { Text("Files") },
                    leadingIcon = { Icon(Icons.Filled.AttachFile, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        openFailure = null
                        filePicker.launch(FeedbackLimits.PICKER_MIME_TYPES)
                    },
                    modifier = Modifier.testTag("fst.settings.feedback.attach.files"),
                )
            }
        }
    }
}

@Composable
private fun AttachmentTile(attachment: FeedbackAttachment, enabled: Boolean, onOpen: () -> Unit, onRemove: () -> Unit) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(null, attachment.id) {
        value = withContext(Dispatchers.IO) { loadThumbnail(context.contentResolver, attachment) }
    }
    Box(Modifier.size(96.dp).testTag("fst.settings.feedback.attachment")) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .padding(top = 6.dp, end = 6.dp)
                .size(88.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(BrandTokens.surfaceMuted)
                .border(1.dp, BrandTokens.glassBorder, RoundedCornerShape(12.dp))
                .clickable(onClick = onOpen)
                .clearAndSetSemantics {
                    contentDescription = attachment.accessibilityLabel
                    role = Role.Button
                    onClick(label = "Open") { onOpen(); true }
                },
        ) {
            thumbnail?.let { Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
            if (attachment.isVideo || thumbnail == null) {
                Icon(
                    if (attachment.isVideo) Icons.Filled.PlayCircle else Icons.Filled.Image,
                    contentDescription = null,
                    tint = BrandTokens.textPrimary,
                    modifier = Modifier.size(36.dp).background(BrandTokens.cardBackground.copy(alpha = 0.55f), CircleShape),
                )
            }
        }
        if (enabled) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 12.dp, y = (-12).dp)
                    .size(48.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Button, onClick = onRemove)
                    .semantics { contentDescription = "Remove ${attachment.name}" }
                    .testTag("fst.settings.feedback.attachment.remove"),
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.size(24.dp).background(BrandTokens.cardBackground, CircleShape).border(1.dp, BrandTokens.textMuted, CircleShape),
                ) {
                    Icon(Icons.Filled.Close, contentDescription = null, tint = BrandTokens.textPrimary, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

// endregion

// region Platform helpers

/**
 * Read a picked URI's display name, size and type (no copy is made).
 *
 * @param resolver Content resolver.
 * @param uri Picked URI.
 * @return Attachment description.
 */
internal fun describe(resolver: ContentResolver, uri: Uri): FeedbackAttachment {
    var name: String? = null
    var size: Long? = null
    runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 && !cursor.isNull(it) }?.let { name = cursor.getString(it) }
                cursor.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !cursor.isNull(it) }?.let { size = cursor.getLong(it) }
            }
        }
    }
    val type = runCatching { resolver.getType(uri) }.getOrNull() ?: "application/octet-stream"
    return FeedbackAttachment(uri.toString(), name ?: uri.lastPathSegment ?: "attachment", type, size?.takeIf { it >= 0 })
}

private fun loadThumbnail(resolver: ContentResolver, attachment: FeedbackAttachment): Bitmap? = runCatching {
    val uri = Uri.parse(attachment.id)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        resolver.loadThumbnail(uri, Size(THUMBNAIL_PX, THUMBNAIL_PX), null)
    } else if (!attachment.isVideo) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= THUMBNAIL_PX && bounds.outHeight / (sample * 2) >= THUMBNAIL_PX) sample *= 2
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
    } else {
        null
    }
}.getOrNull()

private const val THUMBNAIL_PX = 256

/**
 * Hand a URI to the system viewer (the app has no media player).
 *
 * @param context Context.
 * @param uri Content or HTTPS URI.
 * @param mimeType Type hint, or null.
 * @return False when no app can open it.
 */
internal fun openUri(context: Context, uri: Uri, mimeType: String?): Boolean {
    val intent = Intent(Intent.ACTION_VIEW).apply {
        if (mimeType != null) setDataAndType(uri, mimeType) else data = uri
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return try {
        context.startActivity(intent)
        true
    } catch (error: ActivityNotFoundException) {
        false
    } catch (error: SecurityException) {
        false
    }
}

// endregion
