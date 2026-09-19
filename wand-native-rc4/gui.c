#include <gtk/gtk.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *dropdown;
    GtkWidget *setup;
    GtkWidget *verify;
    GtkWidget *play;
    GtkWidget *health;
    GtkWidget *refresh;
    GtkWidget *status;
    GtkWidget *spinner;
    GPtrArray *appids;
    gchar *helper;
} App;

static void set_busy(App *a, gboolean busy) {
    gtk_widget_set_sensitive(a->setup, !busy);
    gtk_widget_set_sensitive(a->verify, !busy);
    gtk_widget_set_sensitive(a->play, !busy);
    gtk_widget_set_sensitive(a->health, !busy);
    gtk_widget_set_sensitive(a->refresh, !busy);
    gtk_widget_set_sensitive(a->dropdown, !busy);
    gtk_widget_set_visible(a->spinner, busy);
    if (busy) gtk_spinner_start(GTK_SPINNER(a->spinner));
    else gtk_spinner_stop(GTK_SPINNER(a->spinner));
}

static void set_status(App *a, const gchar *text) {
    gtk_label_set_text(GTK_LABEL(a->status), text ? text : "");
}

static const gchar *selected_appid(App *a) {
    guint pos = gtk_drop_down_get_selected(GTK_DROP_DOWN(a->dropdown));
    if (!a->appids || pos == GTK_INVALID_LIST_POSITION || pos >= a->appids->len) return NULL;
    return g_ptr_array_index(a->appids, pos);
}

static void finished(GObject *src, GAsyncResult *res, gpointer data) {
    App *a = data;
    gchar *out = NULL;
    gchar *err = NULL;
    GError *error = NULL;
    gboolean ok = g_subprocess_communicate_utf8_finish(G_SUBPROCESS(src), res, &out, &err, &error);
    GString *s = g_string_new("");
    if (out && *out) g_string_append(s, out);
    if (err && *err) {
        if (s->len) g_string_append_c(s, '\n');
        g_string_append(s, err);
    }
    if (!ok || !g_subprocess_get_successful(G_SUBPROCESS(src))) {
        if (s->len) g_string_append_c(s, '\n');
        g_string_append_printf(s, "Action failed%s%s",
            error ? ": " : ".", error ? error->message : "");
    }
    if (!s->len) g_string_append(s, "Done.");
    set_status(a, s->str);
    set_busy(a, FALSE);
    g_string_free(s, TRUE);
    g_clear_error(&error);
    g_free(out);
    g_free(err);
}

static void run_action(App *a, const gchar *action) {
    const gchar *appid = selected_appid(a);
    if (!appid || !*appid) {
        set_status(a, "Select an installed Steam game first.");
        return;
    }

    GError *error = NULL;
    GSubprocess *p = g_subprocess_new(
        G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_MERGE,
        &error, a->helper, action, appid, NULL);
    if (!p) {
        set_status(a, error ? error->message : "Failed to start Wand Native helper.");
        g_clear_error(&error);
        return;
    }
    set_busy(a, TRUE);
    if (g_strcmp0(action, "play") == 0)
        set_status(a, "Launching Wand + game through Steam. Steam will remain running...");
    else if (g_strcmp0(action, "setup") == 0)
        set_status(a, "Setting up Wand Native. A one-time Steam restart happens only if the game mapping needs it...");
    else
        set_status(a, "Working...");
    g_subprocess_communicate_utf8_async(p, NULL, NULL, finished, a);
    g_object_unref(p);
}

static void setup_clicked(GtkButton *b, gpointer d) { (void)b; run_action(d, "setup"); }
static void verify_clicked(GtkButton *b, gpointer d) { (void)b; run_action(d, "verify"); }
static void play_clicked(GtkButton *b, gpointer d) { (void)b; run_action(d, "play"); }
static void health_clicked(GtkButton *b, gpointer d) { (void)b; run_action(d, "health"); }

static void load_games(App *a) {
    gchar *argv[] = { a->helper, "games", NULL };
    gchar *out = NULL, *err = NULL;
    gint status = 0;
    GError *error = NULL;

    if (!g_spawn_sync(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL,
                      &out, &err, &status, &error)) {
        set_status(a, error ? error->message : "Could not scan Steam games.");
        g_clear_error(&error);
        g_free(out); g_free(err);
        return;
    }

    if (a->appids) g_ptr_array_free(a->appids, TRUE);
    a->appids = g_ptr_array_new_with_free_func(g_free);
    GPtrArray *labels = g_ptr_array_new_with_free_func(g_free);

    gchar **lines = g_strsplit(out ? out : "", "\n", -1);
    for (gint i = 0; lines[i]; i++) {
        if (!*lines[i]) continue;
        gchar **parts = g_strsplit(lines[i], "\t", 2);
        if (parts[0] && parts[1] && *parts[0] && *parts[1]) {
            g_ptr_array_add(a->appids, g_strdup(parts[0]));
            g_ptr_array_add(labels, g_strdup_printf("%s  ·  %s", parts[1], parts[0]));
        }
        g_strfreev(parts);
    }
    g_strfreev(lines);

    const gchar **strv = g_new0(const gchar *, labels->len + 1);
    for (guint i = 0; i < labels->len; i++) strv[i] = g_ptr_array_index(labels, i);
    GtkStringList *model = gtk_string_list_new(strv);
    gtk_drop_down_set_model(GTK_DROP_DOWN(a->dropdown), G_LIST_MODEL(model));
    g_object_unref(model);
    g_free(strv);

    if (a->appids->len) {
        gtk_drop_down_set_selected(GTK_DROP_DOWN(a->dropdown), 0);
        set_status(a, "Ready. Setup / Repair once, then use PLAY WITH WAND. Normal play never restarts Steam.");
    } else {
        set_status(a, err && *err ? err : "No installed Steam games were found.");
    }

    g_ptr_array_free(labels, TRUE);
    g_free(out); g_free(err);
}

static void refresh_clicked(GtkButton *b, gpointer d) { (void)b; load_games(d); }

static void activate(GtkApplication *application, gpointer data) {
    (void)data;
    App *a = g_new0(App, 1);

    const gchar *appdir = g_getenv("WAND_APPDIR");
    if (!appdir || !*appdir) appdir = ".";
    a->helper = g_build_filename(appdir, "usr", "lib", "wand-native", "wand-native-helper", NULL);

    a->window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(a->window), "Wand Native");
    gtk_window_set_default_size(GTK_WINDOW(a->window), 720, 520);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 18);
    gtk_widget_set_margin_top(outer, 24);
    gtk_widget_set_margin_bottom(outer, 24);
    gtk_widget_set_margin_start(outer, 28);
    gtk_widget_set_margin_end(outer, 28);
    gtk_window_set_child(GTK_WINDOW(a->window), outer);

    GtkWidget *title = gtk_label_new("Wand Native");
    gtk_widget_add_css_class(title, "title-1");
    gtk_label_set_xalign(GTK_LABEL(title), 0.0);
    gtk_box_append(GTK_BOX(outer), title);

    GtkWidget *subtitle = gtk_label_new("Run Wand and your Steam game together in one Proton session");
    gtk_widget_add_css_class(subtitle, "dim-label");
    gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0);
    gtk_box_append(GTK_BOX(outer), subtitle);

    GtkWidget *sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_append(GTK_BOX(outer), sep);

    GtkWidget *game_label = gtk_label_new("Steam game");
    gtk_label_set_xalign(GTK_LABEL(game_label), 0.0);
    gtk_widget_add_css_class(game_label, "heading");
    gtk_box_append(GTK_BOX(outer), game_label);

    GtkWidget *game_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    a->dropdown = gtk_drop_down_new(NULL, NULL);
    gtk_widget_set_hexpand(a->dropdown, TRUE);
    a->refresh = gtk_button_new_with_label("Refresh");
    g_signal_connect(a->refresh, "clicked", G_CALLBACK(refresh_clicked), a);
    gtk_box_append(GTK_BOX(game_row), a->dropdown);
    gtk_box_append(GTK_BOX(game_row), a->refresh);
    gtk_box_append(GTK_BOX(outer), game_row);

    a->play = gtk_button_new_with_label("PLAY WITH WAND");
    gtk_widget_add_css_class(a->play, "suggested-action");
    gtk_widget_add_css_class(a->play, "pill");
    gtk_widget_set_size_request(a->play, -1, 58);
    g_signal_connect(a->play, "clicked", G_CALLBACK(play_clicked), a);
    gtk_box_append(GTK_BOX(outer), a->play);

    GtkWidget *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    a->setup = gtk_button_new_with_label("Setup / Repair");
    a->verify = gtk_button_new_with_label("Verify");
    a->health = gtk_button_new_with_label("Trainer Health");
    g_signal_connect(a->setup, "clicked", G_CALLBACK(setup_clicked), a);
    g_signal_connect(a->verify, "clicked", G_CALLBACK(verify_clicked), a);
    g_signal_connect(a->health, "clicked", G_CALLBACK(health_clicked), a);
    gtk_box_append(GTK_BOX(buttons), a->setup);
    gtk_box_append(GTK_BOX(buttons), a->verify);
    gtk_box_append(GTK_BOX(buttons), a->health);
    gtk_box_append(GTK_BOX(outer), buttons);

    GtkWidget *status_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    a->spinner = gtk_spinner_new();
    gtk_widget_set_visible(a->spinner, FALSE);
    a->status = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(a->status), 0.0);
    gtk_label_set_yalign(GTK_LABEL(a->status), 0.0);
    gtk_label_set_wrap(GTK_LABEL(a->status), TRUE);
    gtk_label_set_selectable(GTK_LABEL(a->status), TRUE);
    gtk_widget_set_hexpand(a->status, TRUE);
    gtk_box_append(GTK_BOX(status_box), a->spinner);
    gtk_box_append(GTK_BOX(status_box), a->status);
    gtk_box_append(GTK_BOX(outer), status_box);

    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(css,
        "window { background: #171a1f; }"
        "button.suggested-action { font-weight: 700; font-size: 16px; }"
        "label.title-1 { font-size: 28px; font-weight: 700; }"
        "label.heading { font-weight: 600; }");
    gtk_style_context_add_provider_for_display(
        gtk_widget_get_display(a->window), GTK_STYLE_PROVIDER(css),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);

    load_games(a);
    gtk_window_present(GTK_WINDOW(a->window));
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("dev.wand.WandNative", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
