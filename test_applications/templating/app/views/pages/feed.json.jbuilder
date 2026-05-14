json.title "Demo Feed"
json.entries do
  json.array! [{ id: 1, title: "first" }, { id: 2, title: "second" }] do |entry|
    json.id entry[:id]
    json.title entry[:title]
  end
end
