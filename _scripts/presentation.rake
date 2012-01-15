require 'pathname' #modüllerin import edilmesi
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {}) #presentation verisini istiyoruz

PRESENTATION_DIR = CONFIG.fetch('directory', 'p') #directory naahtarını istiyoruz
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html') #PRESENTATION_DIR ile index.html yi birleştir
IMAGE_GEOMETRY = [ 733, 550 ] #resim boyutlarını belirle
DEPEND_KEYS    = %w(source css js) #bağımlı anahtar atanır
DEPEND_ALWAYS  = %w(media) #sürekli bağımlılar %w ile komutun parantez içindekileri dizi haline çevrilir.
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}
#komutlar ve yaptıkları tanımlanır
presentation   = {} #ilklendirme
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd) #dosya yolunu değişkene ata
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path) #dosya yolunun kontrolü
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } : #split edilip listeye eklenmesi
      [path]
  end
end

def png_comment(file, string) #fotoğrafların commentlenmesi
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file) #resmi al
  image.metadata['Comment'] = 'raked' #resimi biçimlendir
  image.save(file) #kaydet
end

def png_optim(file, threshold=40000) #fotoğrafları optimize et
  return if File.new(file).size < threshold #boyutu verilen dosyadan küçük olanları işleme al
  sh "pngnq -f -e .png-nq #{file}" #optimize et
  out = "#{file}-nq" #nq uzantılı dosyaları out değişkenine kaydet
  if File.exist?(out) #nq uzantılı dosya  varmı kontrol et
    $?.success? ? File.rename(out, file) : File.delete(out) #dosyadan nq kısmını sil,yeniden isimlendir
  end
  png_comment(file, 'raked')
end
#png fonksiyonlarının optimizasyonunu yapan kısım 
def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}" #sh komutlarıyla optimize et
  sh "mogrify -comment 'raked' #{file}" #sh komutlarıyla açıkla
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ } #resimleri çıkış formatına göre al
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i] #boyut kontrolü yap
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s #boyut büyükse yeniden boyutlandırma yap
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE) #default_conffile a DEFAULT_CONFFILE i ata

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir| # '. ile başlayanları birleştir
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide #landlide tanımlanmamışsa 
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış" #hata mesajı bas
      exit 1
    end

    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md') #index.md var ise
      base = 'index' 
      ispublic = true #public yap
    elsif File.exists?('presentation.md') #presentation var ise
      base = 'presentation'
      ispublic = false #public yapma
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı" #hata mesajını bas
      exit 1
    end

    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png') #küçük resim oluştur
    target = File.to_herepath(basename)

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v| #etiketleme yap
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten] #yapılacakların hazırlanması

presentation.each do |presentation, data| #sunumu hazırla
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}" #shell ile 'landslide -i' komutuyla sunumu başlat
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do #küçük resmi hedef yap
      next unless data[:public] # sonraki gelen public değilse
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}" #sh de  değişikliği yap
      png_optim(data[:thumbnail])
    end

    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]

    task :build => [:optim, data[:target], :index] #optim olarak belirlenen bagımlılıkların çalışması

    task :view do #dosya oluşturulması
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view] # build ve view görevlerini çalıştır


    task :clean do #işlevi biten kısımlar temizlenir
      rm_f data[:target]
      rm_f data[:thumbnail]
    end

    task :default => :build #inşa işleminin gerçekleşmesi
  end
#ns tablosuna verilen görevleri ata
  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end
#tablodaki her eleman için görevleri yap
namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do 
    index = YAML.load_file(INDEX_FILE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations'] #kosul sağlanmazsa
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml) #indeksi yaz
        f.write("---\n")
      end
    end
  end
#sunum seçimi ve diğer özelliklerin ayarlanması
  desc "sunum menüsü"
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu
end
#presantation un p iletisiyle çalışması sağlanır
desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
