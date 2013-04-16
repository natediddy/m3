#!/usr/bin/env python
#
# m3 (My Movie Manager)
# Nathan Forbes
#

import sys

def m3_err(m):
  sys.stderr.write('m3: error: ' + m + '\n')

def m3_msg(m):
  sys.stdout.write('m3: info: ' + m + '\n')

try:
  import ffvideo
except ImportError:
  m3_err('failed to import \'ffvideo\'')
  sys.exit(1)

try:
  import gobject
except ImportError:
  m3_err('failed to import \'gobject\'')
  sys.exit(1)

try:
  import gtk
except ImportError:
  m3_err('failed to import \'gtk\'')
  sys.exit(1)

import os
import random
import shutil
import subprocess
import threading

data_location = os.path.join(os.path.expanduser('~'), '.m3')
data_location_thumbnails = os.path.join(data_location, 'thumbnails')
default_movie_location = os.path.join(os.path.expanduser('~'), 'Videos')
movie_file_extensions = ['avi', 'divx', 'm4v', 'mp4', 'mkv']
movie_player = 'vlc'

iconview_full_path    = 0
iconview_display_name = 1
iconview_icon         = 2
iconview_is_directory = 3

movie_detail_runtime    = 0
movie_detail_size       = 1
movie_detail_type       = 2
movie_detail_resolution = 3

kilo_factor = long(1024)
mega_factor = kilo_factor * kilo_factor
giga_factor = mega_factor * kilo_factor
tera_factor = giga_factor * kilo_factor
peta_factor = tera_factor * kilo_factor

def m3_movie_random_runtime_second(s):
  n = int(s.duration)
  random.seed()
  # remove %10 of runtime to avoid screenshots of end credits
  return random.randrange(0, n - (n / 10))

def m3_movie_runtime_str(s):
  n = int(s.duration)
  return '%02i:%02i:%02i' % (n / 3600, (n / 60) % 60, n % 60)

def m3_movie_size(p):
  n = os.stat(p).st_size
  if (n / peta_factor) > 0:
    return '%.1fPB' % (float(n) / float(peta_factor))
  elif (n / tera_factor) > 0:
    return '%.1fTB' % (float(n) / float(tera_factor))
  elif (n / giga_factor) > 0:
    return '%.1fGB' % (float(n) / float(giga_factor))
  elif (n / mega_factor) > 0:
    return '%.1fMB' % (float(n) / float(mega_factor))
  elif (n / kilo_factor) > 0:
    return '%.1fkB' % (float(n) / float(kilo_factor))
  return '%iB' % n

def m3_movie_resolution(s):
  return '%ix%i' % (s.width, s.height)

def m3_movie_details(p):
  # [runtime, size, type, resolution]
  ret = ['', '', '', '']
  try:
    s = ffvideo.VideoStream(p)
  except:
    return ret
  ret[movie_detail_runtime] = m3_movie_runtime_str(s)
  ret[movie_detail_size] = m3_movie_size(p)
  ret[movie_detail_type] = s.codec_name
  ret[movie_detail_resolution] = m3_movie_resolution(s)
  return ret

def m3_movie_write_thumbnail(p, tp):
  s = ffvideo.VideoStream(p, frame_size=(128, None))
  s.get_frame_at_sec(m3_movie_random_runtime_second(s)).image().save(tp)

def m3_movie_thumbnail_path(p):
  return os.path.join(os.path.expanduser('~'), data_location_thumbnails,
      p.replace(os.sep, '__SEP__') + '.jpeg')

def m3_movie_thumbnail_gen_check(p):
  tp = m3_movie_thumbnail_path(p)
  if not os.path.isfile(tp):
    m3_movie_write_thumbnail(p, tp)
    if not os.path.isfile(tp):
      m3_err('failed to write thumbnail for \'%s\'' % p)
      return False
  return True

def m3_file_extension(p):
  s = p.rpartition('.')
  if s[0] and s[1] and s[2]:
    return s[2]
  return ''

def m3_file_display_name(p):
  x = m3_file_extension(p)
  if x and x not in movie_file_extensions:
    return os.path.basename(p)
  n = os.path.basename(p).rpartition('.')
  if n[0]:
    n = n[0]
  else:
    n = n[2]
  return n.replace('_', ' ').replace('-', ' ').replace('.', ' ')

def m3_stock_icon(n):
  return gtk.icon_theme_get_default().load_icon(n, 32, 0)

def m3_thumbnail_icon(p):
  x = m3_file_extension(p)
  if x and x in movie_file_extensions and m3_movie_thumbnail_gen_check(p):
    return gtk.gdk.pixbuf_new_from_file(m3_movie_thumbnail_path(p))
  return m3_stock_icon(gtk.STOCK_FILE)

def m3_setup_program_dirs():
  if not os.path.isdir(data_location):
    os.mkdir(data_location)
  if not os.path.isdir(data_location_thumbnails):
    os.mkdir(data_location_thumbnails)

def m3_scan_location(l, ls):
  for x in os.listdir(l):
    if x.startswith('.'):
      continue
    p = os.path.join(l, x)
    n = m3_file_display_name(p)
    if os.path.isdir(p):
      ls.append([p, n, m3_stock_icon(gtk.STOCK_DIRECTORY), True])
    elif os.path.isfile(p):
      if m3_file_extension(x) not in movie_file_extensions:
        continue
      ls.append([p, n, m3_thumbnail_icon(p), False])

class M3GenThumbsProgressDialog(gtk.Window):
  def __init__(self):
    super(M3GenThumbsProgressDialog, self).__init__()
    self.thread = None
    self.set_title('Working')
    self.set_position(gtk.WIN_POS_CENTER)
    self.pbar = gtk.ProgressBar()
    label = gtk.Label('Generating thumbnails...')
    vbox = gtk.VBox(False, 2)
    vbox.pack_start(label, False, False, 0)
    vbox.pack_start(self.pbar, False, False, 0)
    self.add(vbox)
  def run(self, l, ls):
    self.show_all()
    self.thread = threading.Thread(target=self._generate, args=(l, ls))
    self.thread.start()
    gobject.timeout_add(100, self._callback)
  def _generate(self, l, ls):
    m3_scan_location(l, ls)
  def _callback(self, *args):
    if self.thread.is_alive():
      self.pbar.pulse()
      return True
    self.destroy()
    return False

class M3(gtk.Window):
  def __init__(self):
    super(M3, self).__init__()
    self.connect('destroy', gtk.main_quit)
    self.set_title('M3')
    self.set_position(gtk.WIN_POS_CENTER)
    self.set_size_request(600, 400)
    self.set_resizable(True)
    self.list_store = None
    self.movie_location = default_movie_location
    self._setup_interface()
  def _setup_interface(self):
    menu_bar = gtk.MenuBar()
    file_menu = gtk.Menu()
    file_menu_item = gtk.MenuItem('File')
    file_menu_item.set_submenu(file_menu)
    add_media_menu_item = gtk.MenuItem('Add Media...')
    add_media_menu_item.connect('activate', self._new_movie_location)
    file_menu.append(add_media_menu_item)
    quit_menu_item = gtk.MenuItem('Quit')
    quit_menu_item.connect('activate', gtk.main_quit)
    file_menu.append(quit_menu_item)
    menu_bar.append(file_menu_item)
    edit_menu = gtk.Menu()
    edit_menu_item = gtk.MenuItem('Edit')
    edit_menu_item.set_submenu(edit_menu)
    settings_menu_item = gtk.MenuItem('Settings')
    settings_menu_item.connect('activate',
        self._on_settings_menu_item_activated)
    edit_menu.append(settings_menu_item)
    menu_bar.append(edit_menu_item)
    toolbar = gtk.Toolbar()
    back_tool_button = gtk.ToolButton(gtk.STOCK_GO_BACK)
    back_tool_button.connect('clicked', self._on_back_tool_button_clicked)
    back_tool_button.set_tooltip_text('Open parent folder')
    toolbar.insert(back_tool_button, -1)
    open_tool_button = gtk.ToolButton(gtk.STOCK_OPEN)
    open_tool_button.connect('clicked', self._new_movie_location)
    open_tool_button.set_tooltip_text('Open new folder')
    toolbar.insert(open_tool_button, -1)
    quit_tool_button = gtk.ToolButton(gtk.STOCK_QUIT)
    quit_tool_button.connect('clicked', gtk.main_quit)
    quit_tool_button.set_tooltip_text('Exit M3')
    toolbar.insert(quit_tool_button, -1)
    scrolled_window = gtk.ScrolledWindow()
    scrolled_window.set_shadow_type(gtk.SHADOW_ETCHED_IN)
    scrolled_window.set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
    self._create_store()
    self._fill_store()
    icon_view = gtk.IconView(self.list_store)
    icon_view.set_selection_mode(gtk.SELECTION_SINGLE)
    icon_view.set_text_column(iconview_display_name)
    icon_view.set_pixbuf_column(iconview_icon)
    icon_view.connect('button-press-event', self._on_icon_view_button_press)
    scrolled_window.add(icon_view)
    icon_view.grab_focus()
    vbox = gtk.VBox(False, 2)
    vbox.pack_start(menu_bar, False, False, 0)
    vbox.pack_start(toolbar, False, False, 0)
    vbox.pack_start(scrolled_window, True, True, 0)
    self.add(vbox)
  def _create_store(self):
    self.list_store = gtk.ListStore(str, str, gtk.gdk.Pixbuf, bool)
    self.list_store.set_sort_column_id(iconview_full_path, gtk.SORT_ASCENDING)
  def _get_stock_icon(self, name):
    t = gtk.icon_theme_get_default()
    return t.load_icon(name, 32, 0)
  def _get_thumbnail_icon(self, p):
    x = m3_file_extension(p)
    if x and x in movie_file_extensions and m3_movie_thumbnail_gen_check(p):
      return gtk.gdk.pixbuf_new_from_file(m3_movie_thumbnail_path(p))
    return self._get_stock_icon(gtk.STOCK_FILE)
  def _fill_store(self):
    self.list_store.clear()
    if not self.movie_location:
      return
    needs_thumb = False
    for x in os.listdir(self.movie_location):
      p = os.path.join(self.movie_location, x)
      if not os.path.isfile(p):
        continue
      if m3_file_extension(x) in movie_file_extensions:
        if not os.path.isfile(m3_movie_thumbnail_path(p)):
          needs_thumb = True
          break
    if needs_thumb:
      M3GenThumbsProgressDialog().run(self.movie_location, self.list_store)
    else:
      m3_scan_location(self.movie_location, self.list_store)
  def _new_movie_location(self, w):
    dialog = gtk.FileChooserDialog('Open movie location...', None,
        gtk.FILE_CHOOSER_ACTION_OPEN,
        (gtk.STOCK_CANCEL, gtk.RESPONSE_CANCEL, gtk.STOCK_OPEN,
         gtk.RESPONSE_OK))
    dialog.set_default_response(gtk.RESPONSE_OK)
    dialog.set_action(gtk.FILE_CHOOSER_ACTION_SELECT_FOLDER)
    chosen = ''
    if dialog.run() == gtk.RESPONSE_OK:
      chosen = dialog.get_filename()
    dialog.destroy()
    if chosen:
      self.movie_location = chosen
    m3_msg('chose ' + self.movie_location)
    self._fill_store()
  def _on_settings_menu_item_activated(self, w):
    m3_msg('settings menu item activated')
  def _on_back_tool_button_clicked(self, w):
    self.movie_location = os.path.dirname(self.movie_location)
    self._fill_store()
  def _on_add_tool_button_clicked(self, w):
    m3_msg('add tool button clicked')
  def _on_home_tool_button_clicked(self, w):
    m3_msg('home tool button clicked')
  #def _on_icon_view_item_activated(self, w, i):
  #  m = w.get_model()
  #  if m[i][iconview_is_directory]:
  #    self.movie_location = m[i][iconview_full_path]
  #    self._fill_store()
  #  else:
  #    subprocess.Popen([movie_player, m[i][iconview_full_path]],
  #        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  def _on_icon_view_button_press(self, w, e):
    i = w.get_path_at_pos(int(e.x), int(e.y))
    m = w.get_model()
    if e.button == 1:
      if m[i][iconview_is_directory]:
        self.movie_location = m[i][iconview_full_path]
        self._fill_store()
      else:
        subprocess.Popen([movie_player, m[i][iconview_full_path]],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    elif e.button == 3:
      if not m[i][iconview_is_directory]:
        details = m3_movie_details(m[i][iconview_full_path])
        p = gtk.Menu()
        i1 = gtk.MenuItem('Runtime:      ' + details[movie_detail_runtime])
        i2 = gtk.MenuItem('Size:                ' + details[movie_detail_size])
        i3 = gtk.MenuItem('Codec:           ' + details[movie_detail_type])
        i4 = gtk.MenuItem('Resolution: ' + details[movie_detail_resolution])
        i1.show()
        i2.show()
        i3.show()
        i4.show()
        p.append(i1)
        p.append(i2)
        p.append(i3)
        p.append(i4)
        p.popup(None, None, None, e.button, e.time, None)
    return True
  def run(self):
    self.show_all()
    gtk.main()

def main():
  gobject.threads_init()
  m3_setup_program_dirs()
  M3().run()

if __name__ == '__main__':
  main()
