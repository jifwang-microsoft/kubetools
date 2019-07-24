const express = require('express')
const app = express()
const port = 3000

// connect to elastic search using url from envionment variable
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: `http://external-elasticsearch:5000` })

app.get('/', (req, res) => {
    res.json({ message: "Yup everything works" })
})


// create data 
app.get('/insertData', (req, res) => {
    var today = new Date();
    client.index({
        index: 'game-of-thrones',
        body: {
            character: 'Daenerys Targaryen',
            quote: 'I am the blood of the dragon.',
            date: today
        }
    }, (err, result) => {
        if (err) {
            res.send(err)
        } else {
            res.json({ data: result.body })
        }
    })
})

// read data 

app.get('/readData', (req, res) => {
    client.search({
        index: 'game-of-thrones',
        body: {
            query: {
                match: { quote: 'blood' }
            }
        }
    }, (err, result) => {
        if (err) {
            res.send(err)
        } else {
            res.json({ data: result.body })
        }
    })
})

app.listen(port, () => console.log(`Example app listening on port ${port}!`))