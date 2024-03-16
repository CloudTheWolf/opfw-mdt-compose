import axios from 'axios';

export const setupAxios = () => {
    axios.defaults.baseURL = 'https://pd-server.mysite.com/'
};

