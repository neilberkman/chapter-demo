# frozen_string_literal: true

require 'taglib'
require 'open3'

class ChapDemo
  INPUT_DIR = 'chapters'
  OUTPUT_DIR = 'output'

  CHAPTER_INFOS = [
    {
      title: 'The Walrus and the Carpenter',
      audio: 'walrus.mp3',
      image: 'walrus.jpg',
      url: 'https://www.poetryfoundation.org/poems/43914/the-walrus-and-the-carpenter-56d222cbc80a9'
    },
    {
      title: 'The Charge of the Light Brigade',
      audio: 'light_brigade.mp3',
      image: 'light_brigade.jpg',
      url: 'https://www.poetryfoundation.org/poems/45319/the-charge-of-the-light-brigade'
    },
    {
      title: 'The Raven',
      audio: 'raven.mp3',
      image: 'raven.jpg',
      url: 'https://www.poetryfoundation.org/poems/48860/the-raven'
    }
  ].freeze

  def go
    episode_file = create_episode(chapter_infos)
    add_tags(episode_file, chapter_infos)
  end

  def chapter_infos
    @chapter_infos ||=
      CHAPTER_INFOS.map do |chapter_info|
        chapter_info.merge(duration_ms: duration_ms(chapter_info[:audio]))
      end
  end

  def add_tags(mp3_file_path, chapter_infos)
    TagLib::MPEG::File.open(mp3_file_path) do |mp3_file|
      tag = mp3_file.id3v2_tag

      tag.title = 'Poems, episode 1'

      tag.add_frame(
        build_toc(chapter_infos)
      )

      prev_end_time = 0
      chapter_infos.each_with_index do |chapter_info, i|
        tag.add_frame(
          build_chapter_frame(chapter_info, prev_end_time, i + 1)
        )
        prev_end_time += chapter_info[:duration_ms]
      end

      mp3_file.save
    end
  end

  def build_toc(chapter_infos)
    toc = TagLib::ID3v2::TableOfContentsFrame.new('CTOC')
    toc.is_top_level = true
    toc.is_ordered = true

    chapter_infos.each_with_index do |_chapter_info, i|
      toc.add_child_element(chapter_element_id(i + 1))
    end

    toc.add_embedded_frame(
      build_title_frame('Table of Contents')
    )

    toc
  end

  def build_chapter_frame(chapter_info, prev_end_time, chapter_num)
    element_id = chapter_element_id(chapter_num)

    frames = [
      build_title_frame(chapter_info[:title]),
      build_image_frame(chapter_info[:image]),
      build_url_frame(chapter_info[:url])
    ]

    start_time = prev_end_time + 1
    end_time = prev_end_time + chapter_info[:duration_ms]
    # if endTime is 0xFFFFFFFF, start / end time is used instead.
    start_offset = 0xFFFFFFFF
    end_offset = 0xFFFFFFFF

    chap_frame = TagLib::ID3v2::ChapterFrame.new(
      element_id,
      start_time.to_i,
      end_time.to_i,
      start_offset.to_i,
      end_offset.to_i
    )

    frames.each do |frame|
      chap_frame.add_embedded_frame(frame)
    end

    chap_frame
  end

  def chapter_element_id(chap_num)
    "CH#{chap_num}"
  end

  def build_title_frame(text)
    build_text_id_frame('TIT2', text)
  end

  def build_text_id_frame(frame_id, text)
    TagLib::ID3v2::TextIdentificationFrame.new(
      frame_id,
      TagLib::String::Latin1
    ).tap { |text_id_frame| text_id_frame.text = text }
  end

  def build_url_frame(url)
    TagLib::ID3v2::UserUrlLinkFrame.new.tap do |url_frame|
      url_frame.description = 'chapter URL'
      url_frame.url = url
    end
  end

  def build_image_frame(file_path)
    TagLib::ID3v2::AttachedPictureFrame.new.tap do |image_frame|
      image_frame.mime_type = 'image/jpeg'
      image_frame.type = TagLib::ID3v2::AttachedPictureFrame::Media
      image_frame.picture = File.open(input_file_path(file_path), 'rb', &:read)
    end
  end

  def create_episode(chapter_infos)
    Dir.mkdir OUTPUT_DIR unless Dir.exist? OUTPUT_DIR
    output_file = "#{OUTPUT_DIR}/episode.mp3"
    chapter_files = chapter_infos.map do |chapter_info|
      input_file_path(chapter_info[:audio])
    end.join(' ')

    cmd = "sox #{chapter_files} #{output_file}"
    _stdout, _stderr, _status = Open3.capture3(cmd)

    output_file
  end

  def duration_ms(filename)
    audio_attrs(filename)['Length (seconds)'].to_i * 1000
  end

  def audio_attrs(path)
    cmd = "sox #{input_file_path(path)} -n stat"
    _stdout, stderr, _status = Open3.capture3(cmd)
    pairs = stderr.split("\n").map { |line| line.split(':') }
    pairs.each_with_object({}) do |pair, acc|
      acc[pair[0]] = pair[1].to_f
    end
  end

  def input_file_path(filename)
    File.join(INPUT_DIR, filename)
  end
end
