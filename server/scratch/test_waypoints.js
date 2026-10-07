const axios = require("axios");
const fs = require("fs");
async function test() {
  try {
    const res = await axios.post("https://api.olamaps.io/routing/v1/directions", null, {
      params: {
        origin: "12.9715987,77.5945627",
        destination: "11.8315,76.0827",
        waypoints: "12.4,76.8",
        api_key: "Txtd52X2o49O1UlPk7euny0DUhjd65VGQaMWzBoR"
      }
    });
    fs.writeFileSync("server/scratch/waypoint_output.json", JSON.stringify(res.data, null, 2));
    console.log("Written!");
  } catch (err) {
    console.error(err.response.data);
  }
}
test();
