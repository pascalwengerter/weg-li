# frozen_string_literal: true

require "geocoder/results/nominatim"
require "geocoder/results/opencagedata"

class DataSet < ApplicationRecord
  # TODO: (PS) do we need polymorphism here?
  belongs_to :setable, polymorphic: true
  belongs_to :keyable, polymorphic: true

  enum kind: { google_vision: 0, exif: 1, car_ml: 2, geocoder: 3, proximity: 4 }

  def charges
    case kind
    when "proximity"
      # [{"charge"=>"Parken weniger als 5 Meter vor/hinter der Kreuzung/Einmündung", "count"=>2, "distance"=>0.0, "diff"=>0.0}]
      data.map { |it| it["charge"] }.compact
    else
      raise "not supported by #{kind}"
    end
  end

  def registrations
    case kind
    when "google_vision"
      district = (setable.district || setable.user.district)
      with_likelyhood =
        Annotator.grep_text(data.deep_symbolize_keys) do |it|
          Vehicle.plate?(it, prefixes: district&.prefixes)
        end
      Vehicle.by_likelyhood(with_likelyhood)
    when "car_ml"
      data["suggestions"]["license_plate_number"]
    else
      raise "not supported by #{kind}"
    end
  end

  def brands
    case kind
    when "google_vision"
      with_likelyhood =
        Annotator.grep_text(data.deep_symbolize_keys) do |it|
          Vehicle.brand?(it)
        end
      Vehicle.by_likelyhood(with_likelyhood)
    when "car_ml"
      data["suggestions"]["make"]
    else
      raise "not supported by #{kind}"
    end
  end

  def colors
    case kind
    when "google_vision"
      with_likelyhood = Annotator.dominant_colors(data.deep_symbolize_keys)
      Vehicle.by_likelyhood(with_likelyhood)
    when "car_ml"
      data["suggestions"]["color"]
    else
      raise "not supported by #{kind}"
    end
  end

  def address
    case kind
    when "geocoder"
      if data.present?
        result_klass =
          (
            if Geocoder.config.lookup == :nominatim
              Geocoder::Result::Nominatim
            else
              Geocoder::Result::Opencagedata
            end
          )
        result = result_klass.new(data.first["data"])
        Notice.geocode_data(result)
      end
    else
      raise "not supported by #{kind}"
    end
  end

  def coords
    case kind
    when "exif"
      if data["latitude"].to_f.positive? && data["longitude"].to_f.positive?
        [data["latitude"], data["longitude"]]
      end
    else
      raise "not supported by #{kind}"
    end
  end

  def date_time
    case kind
    when "exif"
      begin
        Time.zone.parse(data["date_time"])
      rescue StandardError
        nil
      end
    else
      raise "not supported by #{kind}"
    end
  end
end
