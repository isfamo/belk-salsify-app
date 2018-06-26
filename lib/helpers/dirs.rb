class Dirs

  def self.recursive_init_dir(path)
    new.recursive_init_dir(path, 0)
  end

  def recursive_init_dir(path, level)
    pieces = path.split('/')
    return if level >= pieces.length
    dir = pieces[0..level].join('/')
    Dir.mkdir(dir) unless File.exists?(dir)
    recursive_init_dir(path, level + 1)
  end

end
