from django.urls import path
from django.views.generic import TemplateView

from . import views

urlpatterns = [
    path("", TemplateView.as_view(template_name="pages/home.html"), name="home"),
    path("favicon.svg", views.favicon),
    path("robots.txt", TemplateView.as_view(template_name="pages/robots.txt", content_type="text/plain")),
    path("sitemap.xml", TemplateView.as_view(template_name="pages/sitemap.xml", content_type="application/xml")),
]
