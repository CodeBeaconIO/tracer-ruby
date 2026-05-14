xml.instruct!
xml.feed do
  xml.title("Demo Feed")
  xml.entry do
    xml.id("urn:demo:1")
    xml.title("first")
  end
  xml.entry do
    xml.id("urn:demo:2")
    xml.title("second")
  end
end
