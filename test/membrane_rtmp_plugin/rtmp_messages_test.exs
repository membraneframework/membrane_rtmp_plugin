defmodule Membrane.RTMP.MessagesTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Messages.AdditionalMedia
  alias Membrane.RTMP.Messages.Anonymous
  alias Membrane.RTMP.Messages.Connect
  alias Membrane.RTMP.Messages.CreateStream
  alias Membrane.RTMP.Messages.DeleteStream
  alias Membrane.RTMP.Messages.FCPublish
  alias Membrane.RTMP.Messages.OnExpectAdditionalMedia
  alias Membrane.RTMP.Messages.OnMetaData
  alias Membrane.RTMP.Messages.Publish
  alias Membrane.RTMP.Messages.ReleaseStream
  alias Membrane.RTMP.Messages.SetDataFrame

  test "Connect accepts @connect alias" do
    props = %{"app" => "live", "tcUrl" => "rtmp://localhost/live", "custom" => "value"}

    assert Connect.from_data(["@connect", 1, props]) == Connect.from_data(["connect", 1, props])
  end

  test "CreateStream accepts @createStream alias" do
    assert CreateStream.from_data(["@createStream", 2, :null]) ==
             CreateStream.from_data(["createStream", 2, :null])
  end

  test "DeleteStream accepts @deleteStream alias" do
    assert DeleteStream.from_data(["@deleteStream", 3, :null, 10]) ==
             DeleteStream.from_data(["deleteStream", 3, :null, 10])
  end

  test "FCPublish accepts @FCPublish alias" do
    assert FCPublish.from_data(["@FCPublish", 4, :null, "stream_key"]) ==
             FCPublish.from_data(["FCPublish", 4, :null, "stream_key"])
  end

  test "Publish accepts @publish alias with publish type" do
    assert Publish.from_data(["@publish", 5, :null, "stream_key", "live"]) ==
             Publish.from_data(["publish", 5, :null, "stream_key", "live"])
  end

  test "Publish accepts @publish alias without publish type" do
    assert Publish.from_data(["@publish", 6, :null, "stream_key"]) ==
             Publish.from_data(["publish", 6, :null, "stream_key"])
  end

  test "ReleaseStream accepts @releaseStream alias" do
    assert ReleaseStream.from_data(["@releaseStream", 7, :null, "stream_key"]) ==
             ReleaseStream.from_data(["releaseStream", 7, :null, "stream_key"])
  end

  test "AdditionalMedia accepts @additionalMedia alias" do
    props = %{"id" => "track-1", "media" => <<1, 2, 3>>}

    assert AdditionalMedia.from_data(["@additionalMedia", props]) ==
             AdditionalMedia.from_data(["additionalMedia", props])
  end

  test "Anonymous strips @ prefix" do
    props = %{"level" => "status"}

    assert Anonymous.from_data(["@onStatus", props]) ==
             Anonymous.from_data(["onStatus", props])
  end

  test "OnMetaData accepts @onMetaData alias" do
    props = %{"duration" => 12.0, "width" => 1920.0}

    assert OnMetaData.from_data(["@onMetaData", props]) ==
             OnMetaData.from_data(["onMetaData", props])
  end

  test "SetDataFrame accepts nested @onMetaData alias" do
    props = %{"duration" => 12.0, "width" => 1920.0}

    assert SetDataFrame.from_data(["@setDataFrame", "@onMetaData", props]) ==
             SetDataFrame.from_data(["@setDataFrame", "onMetaData", props])
  end

  test "SetDataFrame accepts nested @onExpectAdditionalMedia alias" do
    props = %{
      "additionalMedia" => %{"id" => "track-1"},
      "defaultMedia" => %{"id" => "track-0"},
      "processingIntents" => ["transcode"]
    }

    assert SetDataFrame.from_data(["@setDataFrame", "@onExpectAdditionalMedia", props]) ==
             SetDataFrame.from_data(["@setDataFrame", "onExpectAdditionalMedia", props])
  end

  test "OnExpectAdditionalMedia accepts nested @onExpectAdditionalMedia alias" do
    props = %{
      "additionalMedia" => %{"id" => "track-1"},
      "defaultMedia" => %{"id" => "track-0"},
      "processingIntents" => ["transcode"]
    }

    assert OnExpectAdditionalMedia.from_data(["@setDataFrame", "@onExpectAdditionalMedia", props]) ==
             OnExpectAdditionalMedia.from_data([
               "@setDataFrame",
               "onExpectAdditionalMedia",
               props
             ])
  end
end
